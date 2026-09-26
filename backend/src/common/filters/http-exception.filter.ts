import { ArgumentsHost, Catch, ExceptionFilter, HttpException, HttpStatus, Logger } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { Response } from 'express';

/// Normalises every error response (validation failures, thrown
/// HttpExceptions, and anything unexpected) to the same
/// `{ statusCode, message, error }` shape, and logs the ones that aren't
/// ordinary 4xx client errors — the Flutter client can rely on this shape
/// without special-casing per endpoint.
///
/// Also translates a raw Prisma unique-constraint violation (P2002) into a
/// 409 Conflict rather than falling through to a generic 500 — this fires
/// whenever two concurrent requests both pass a `findUnique`-based
/// existence check before either write lands (e.g. two near-simultaneous
/// signups for the same email, or two bootstrap-first-admin calls), since
/// neither AuthService.signup nor AdminService.createAdminAccount wraps
/// that check-then-create pair in a transaction.
@Catch()
export class HttpExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger('ExceptionFilter');

  catch(exception: unknown, host: ArgumentsHost): void {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();

    if (exception instanceof Prisma.PrismaClientKnownRequestError && exception.code === 'P2002') {
      response.status(HttpStatus.CONFLICT).json({
        statusCode: HttpStatus.CONFLICT,
        message: 'A record with these details already exists.',
        error: 'ConflictException',
      });
      return;
    }

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
