// The WorkerEntrypoint base class, as workerd provides it: the constructor
// keeps the execution context and the env.
export class WorkerEntrypoint<E = unknown> {
  ctx: ExecutionContext;
  env: E;
  constructor(ctx: ExecutionContext, env: E) {
    this.ctx = ctx;
    this.env = env;
  }
}
