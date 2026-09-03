variable "name_prefix"       { type = string }
variable "ecs_cluster_name"  { type = string }
variable "ecs_service_name"  { type = string }
variable "alb_arn_suffix"    { type = string }
variable "alarm_actions"     { type = list(string); default = [] }
