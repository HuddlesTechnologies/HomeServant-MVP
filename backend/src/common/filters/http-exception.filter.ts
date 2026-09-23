import { ArgumentsHost, Catch, ExceptionFilter, HttpException, HttpStatus, Logger } from '@nestjs/common';
import { Response } from 'express';

/// Normalises every error response (validation failures, thrown
/// HttpExceptions, and anything unexpected) to the same
/// `{ statusCode, message, error }` shape, and logs the ones that aren't
/// ordinary 4xx client errors — the Flutter client can rely on this shape
/// without special-casing per endpoint.
@Catch()
export class HttpExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger('ExceptionFilter');

  catch(exception: unknown, host: ArgumentsHost): void {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();

    const isHttp = exception instanceof HttpException;
    const status = isHttp ? exception.getStatus() : HttpStatus.INTERNAL_SERVER_ERROR;
    const body = isHttp ? exception.getResponse() : null;

    const message =
      typeof body === 'string'
        ? body
        : ((body as Record<string, unknown>)?.message ?? 'Something went wrong. Please try again.');

    if (!isHttp || status >= 500) {
      this.logger.error(exception instanceof Error ? exception.stack : exception);
    }

    response.status(status).json({
      statusCode: status,
      message,
      error: isHttp ? exception.name : 'InternalServerError',
    });
  }
}
