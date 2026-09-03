import express from 'express';
import { tracingMiddleware } from './lib/middleware/tracing';
import { initializeTracing } from './lib/monitoring';

// Initialize OpenTelemetry tracing
const tracingSDK = initializeTracing();

const app = express();

// Add tracing middleware BEFORE routes
app.use(tracingMiddleware);

// ... rest of your app configuration ...

// Graceful shutdown
process.on('SIGTERM', async () => {
  console.log('Received SIGTERM, shutting down gracefully...');
  if (tracingSDK) {
    await tracingSDK.shutdown();
  }
  process.exit(0);
});

process.on('SIGINT', async () => {
  console.log('Received SIGINT, shutting down gracefully...');
  if (tracingSDK) {
    await tracingSDK.shutdown();
  }
  process.exit(0);
});

export default app;
