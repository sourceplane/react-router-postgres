declare module "@web/api/books-service.js" {
  export class BooksService {
    constructor(ctx: unknown, env: unknown);
    getBooks(options?: { genre?: string | null; sort?: string | null }): Promise<any>;
    getBook(bookId: string): Promise<any>;
    getRelatedBooks(bookId: string): Promise<any>;
    getHealth(): Promise<any>;
  }
}
declare module "@web/api/index.js" {
  const worker: { fetch(request: Request, env: unknown, ctx: unknown): Promise<Response> };
  export default worker;
}
