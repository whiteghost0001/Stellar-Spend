import json
import boto3
import os
from datetime import datetime, timedelta

ce_client = boto3.client('ce')
ec2_client = boto3.client('ec2')
rds_client = boto3.client('rds')
cw_client = boto3.client('cloudwatch')
sns_client = boto3.client('sns')

SNS_TOPIC_ARN = os.environ['SNS_TOPIC_ARN']
ENVIRONMENT = os.environ['ENVIRONMENT']

# Thresholds
EC2_LOW_CPU_THRESHOLD = 10.0      # percent
RDS_LOW_CONN_THRESHOLD = 5.0      # connections
COST_SPIKE_PCT = 20.0             # percent above baseline
LOOKBACK_DAYS = 30
SPIKE_WINDOW_DAYS = 7


def handler(event, context):
    """Lambda: analyze costs and send optimization recommendations."""
    recommendations = []
    recommendations.extend(analyze_ec2_instances())
    recommendations.extend(analyze_rds_instances())
    recommendations.extend(analyze_cost_trends())

    if recommendations:
        send_recommendations(recommendations)

    return {
        'statusCode': 200,
        'body': json.dumps({
            'recommendations': len(recommendations),
            'timestamp': datetime.utcnow().isoformat()
        })
    }


# ── CloudWatch helpers ────────────────────────────────────────────────────────

def get_cw_average(namespace, metric_name, dimensions, days=7):
    """Return the average value of a CloudWatch metric over the last N days."""
    end = datetime.utcnow()
    start = end - timedelta(days=days)
    try:
        response = cw_client.get_metric_statistics(
            Namespace=namespace,
            MetricName=metric_name,
            Dimensions=dimensions,
            StartTime=start,
            EndTime=end,
            Period=int(days * 86400),
            Statistics=['Average']
        )
        datapoints = response.get('Datapoints', [])
        if datapoints:
            return datapoints[0]['Average']
    except Exception as e:
        print(f"CloudWatch query failed ({namespace}/{metric_name}): {e}")
    return None


# ── EC2 analysis ──────────────────────────────────────────────────────────────

def analyze_ec2_instances():
    recommendations = []
    try:
        response = ec2_client.describe_instances(
            Filters=[
                {'Name': 'instance-state-name', 'Values': ['running']},
                {'Name': 'tag:Project', 'Values': ['stellar-spend']},
                {'Name': 'tag:Environment', 'Values': [ENVIRONMENT]},
            ]
        )
        for reservation in response['Reservations']:
            for instance in reservation['Instances']:
                instance_id = instance['InstanceId']
                instance_type = instance['InstanceType']
                dimensions = [{'Name': 'InstanceId', 'Value': instance_id}]

                cpu_avg = get_cw_average('AWS/EC2', 'CPUUtilization', dimensions)
                if cpu_avg is not None and cpu_avg < EC2_LOW_CPU_THRESHOLD:
                    recommendations.append({
                        'type': 'EC2_DOWNSIZE',
                        'resource': instance_id,
                        'current_type': instance_type,
                        'recommendation': (
                            f'Instance {instance_id} ({instance_type}) has avg CPU '
                            f'{cpu_avg:.1f}% — consider downsizing.'
                        ),
                        'potential_savings': estimate_ec2_savings(instance_type),
                    })

                net_out = get_cw_average('AWS/EC2', 'NetworkOut', dimensions)
                if cpu_avg is not None and cpu_avg < 2.0 and (net_out is None or net_out < 10240):
                    recommendations.append({
                        'type': 'EC2_TERMINATE',
                        'resource': instance_id,
                        'recommendation': (
                            f'Instance {instance_id} appears idle '
                            f'(CPU {cpu_avg:.1f}%, NetworkOut {net_out}). Consider terminating.'
                        ),
                        'potential_savings': estimate_ec2_cost(instance_type),
                    })
    except Exception as e:
        print(f"Error analyzing EC2: {e}")
    return recommendations


# ── RDS analysis ──────────────────────────────────────────────────────────────

def analyze_rds_instances():
    recommendations = []
    try:
        response = rds_client.describe_db_instances(
            Filters=[{'Name': 'engine', 'Values': ['postgres']}]
        )
        for db in response['DBInstances']:
            # Only analyze instances tagged for this environment
            tags = {t['Key']: t['Value'] for t in db.get('TagList', [])}
            if tags.get('Environment') != ENVIRONMENT:
                continue

            db_id = db['DBInstanceIdentifier']
            db_class = db['DBInstanceClass']
            dimensions = [{'Name': 'DBInstanceIdentifier', 'Value': db_id}]

            conn_avg = get_cw_average('AWS/RDS', 'DatabaseConnections', dimensions)
            if conn_avg is not None and conn_avg < RDS_LOW_CONN_THRESHOLD:
                recommendations.append({
                    'type': 'RDS_DOWNSIZE',
                    'resource': db_id,
                    'current_class': db_class,
                    'recommendation': (
                        f'Database {db_id} ({db_class}) has avg {conn_avg:.1f} connections '
                        f'— consider downsizing.'
                    ),
                    'potential_savings': estimate_rds_savings(db_class),
                })

            free_storage = get_cw_average('AWS/RDS', 'FreeStorageSpace', dimensions)
            allocated_gb = db.get('AllocatedStorage', 0)
            if free_storage is not None and allocated_gb > 0:
                free_gb = free_storage / (1024 ** 3)
                free_pct = (free_gb / allocated_gb) * 100
                if free_pct > 60:
                    recommendations.append({
                        'type': 'RDS_STORAGE',
                        'resource': db_id,
                        'recommendation': (
                            f'Database {db_id} has {free_pct:.0f}% free storage '
                            f'({free_gb:.0f} GB / {allocated_gb} GB). Consider reducing allocation.'
                        ),
                        'potential_savings': estimate_storage_savings(free_gb),
                    })
    except Exception as e:
        print(f"Error analyzing RDS: {e}")
    return recommendations


# ── Cost trend analysis ───────────────────────────────────────────────────────

def analyze_cost_trends():
    recommendations = []
    try:
        end_date = datetime.utcnow().date()
        start_date = end_date - timedelta(days=LOOKBACK_DAYS)

        response = ce_client.get_cost_and_usage(
            TimePeriod={'Start': start_date.isoformat(), 'End': end_date.isoformat()},
            Granularity='DAILY',
            Metrics=['UnblendedCost'],
            Filter={'Tags': {'Key': 'Project', 'Values': ['stellar-spend']}},
        )

        costs = [
            float(r['Total']['UnblendedCost']['Amount'])
            for r in response['ResultsByTime']
        ]

        if len(costs) > SPIKE_WINDOW_DAYS:
            baseline_avg = sum(costs[:-SPIKE_WINDOW_DAYS]) / len(costs[:-SPIKE_WINDOW_DAYS])
            recent_avg = sum(costs[-SPIKE_WINDOW_DAYS:]) / SPIKE_WINDOW_DAYS

            if baseline_avg > 0 and recent_avg > baseline_avg * (1 + COST_SPIKE_PCT / 100):
                increase_pct = ((recent_avg - baseline_avg) / baseline_avg) * 100
                recommendations.append({
                    'type': 'COST_SPIKE',
                    'recommendation': (
                        f'Costs rose {increase_pct:.1f}% in the last {SPIKE_WINDOW_DAYS} days. Investigate.'
                    ),
                    'current_daily_avg': f'${recent_avg:.2f}',
                    'previous_daily_avg': f'${baseline_avg:.2f}',
                })
    except Exception as e:
        print(f"Error analyzing cost trends: {e}")
    return recommendations


# ── Estimation helpers ────────────────────────────────────────────────────────

_EC2_HOURLY = {
    't3.micro': 0.0104, 't3.small': 0.0208, 't3.medium': 0.0416,
    't3.large': 0.0832, 't3.xlarge': 0.1664, 't3.2xlarge': 0.3328,
}

def estimate_ec2_savings(instance_type):
    hourly = _EC2_HOURLY.get(instance_type, 0.05)
    monthly = hourly * 720
    savings = monthly * 0.4  # ~40% downsize savings
    return f'~${savings:.0f}/month'

def estimate_ec2_cost(instance_type):
    hourly = _EC2_HOURLY.get(instance_type, 0.05)
    return f'~${hourly * 720:.0f}/month'

def estimate_rds_savings(db_class):
    # Rough half-step downsize savings
    savings_map = {
        'db.t3.small': 15, 'db.t3.medium': 30, 'db.t3.large': 60,
        'db.t3.xlarge': 120, 'db.r5.large': 200,
    }
    return f'~${savings_map.get(db_class, 50)}/month'

def estimate_storage_savings(free_gb):
    # ~$0.115/GB/month for gp2
    return f'~${free_gb * 0.115 * 0.5:.0f}/month'


# ── SNS notification ──────────────────────────────────────────────────────────

def send_recommendations(recommendations):
    message = f"Cost Optimization Recommendations — {ENVIRONMENT}\n"
    message += "=" * 60 + "\n\n"

    for i, rec in enumerate(recommendations, 1):
        message += f"{i}. [{rec['type']}]\n"
        if 'resource' in rec:
            message += f"   Resource: {rec['resource']}\n"
        message += f"   {rec['recommendation']}\n"
        if 'potential_savings' in rec:
            message += f"   Potential savings: {rec['potential_savings']}\n"
        if 'current_daily_avg' in rec:
            message += f"   Recent avg: {rec['current_daily_avg']}/day  Baseline: {rec['previous_daily_avg']}/day\n"
        message += "\n"

    try:
        sns_client.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=f'[{ENVIRONMENT}] Cost Optimization Recommendations ({len(recommendations)} items)',
            Message=message,
        )
        print(f"Sent {len(recommendations)} recommendations via SNS")
    except Exception as e:
        print(f"Error sending SNS notification: {e}")
