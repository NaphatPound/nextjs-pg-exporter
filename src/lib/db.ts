import { Pool } from "pg";
import { readEnv } from "./env";

declare global {
  // eslint-disable-next-line no-var
  var __pgPool: Pool | undefined;
}

export function getPool(): Pool {
  if (global.__pgPool) return global.__pgPool;

  const env = readEnv();

  const pool = new Pool({
    host: env.DB_HOST,
    port: env.DB_PORT,
    database: env.DB_NAME,
    user: env.DB_USER,
    password: env.DB_PASSWORD,
    max: env.DB_POOL_MAX,
    idleTimeoutMillis: env.DB_POOL_IDLE_MS,
    ssl: env.DB_SSL ? { rejectUnauthorized: false } : undefined,
  });

  pool.on("error", (err) => {
    // eslint-disable-next-line no-console
    console.error("PG pool error:", err);
  });

  global.__pgPool = pool;
  return pool;
}
