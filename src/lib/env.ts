export type Env = {
  DB_HOST: string;
  DB_PORT: number;
  DB_NAME: string;
  DB_USER: string;
  DB_PASSWORD: string;
  DB_SSL: boolean;
  DB_POOL_MAX: number;
  DB_POOL_IDLE_MS: number;
  EXPORT_BATCH_SIZE: number;
};

function must(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`Missing env: ${name}`);
  return v;
}

export function readEnv(): Env {
  return {
    DB_HOST: must("DB_HOST"),
    DB_PORT: Number(process.env.DB_PORT ?? "5432"),
    DB_NAME: must("DB_NAME"),
    DB_USER: must("DB_USER"),
    DB_PASSWORD: must("DB_PASSWORD"),
    DB_SSL: (process.env.DB_SSL ?? "false").toLowerCase() === "true",
    DB_POOL_MAX: Number(process.env.DB_POOL_MAX ?? "5"),
    DB_POOL_IDLE_MS: Number(process.env.DB_POOL_IDLE_MS ?? "30000"),
    EXPORT_BATCH_SIZE: Number(process.env.EXPORT_BATCH_SIZE ?? "200"),
  };
}
