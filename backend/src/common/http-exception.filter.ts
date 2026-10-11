import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import { Response } from 'express';

@Catch()
export class HttpExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger('ExceptionFilter');

  catch(exception: unknown, host: ArgumentsHost) {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();

    const isHttp = exception instanceof HttpException;
    const status = isHttp
      ? exception.getStatus()
      : HttpStatus.INTERNAL_SERVER_ERROR;

    const body = isHttp ? exception.getResponse() : null;
    const code =
      typeof body === 'object' && body && 'code' in (body as any)
        ? (body as any).code
        : isHttp
          ? exception.constructor.name.replace('Exception', '').toUpperCase()
          : 'INTERNAL_SERVER_ERROR';
    const message =
      typeof body === 'object' && body && 'message' in (body as any)
        ? (body as any).message
        : isHttp
          ? exception.message
          : 'An unexpected error occurred.';

    if (!isHttp) {
      this.logger.error(exception instanceof Error ? exception.stack : exception);
    }

    response.status(status).json({
      success: false,
      error: { code, message },
    });
  }
}
