import { Logger, ValidationPipe } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { NestFactory } from '@nestjs/core';
import { IoAdapter } from '@nestjs/platform-socket.io';
import { AppModule } from './app.module';
import { HttpExceptionFilter } from './common/filters/http-exception.filter';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  const config = app.get(ConfigService);
  // ChatGateway's realtime message delivery needs this — without it,
  // @WebSocketGateway is registered but nothing actually listens for
  // socket.io connections.
  app.useWebSocketAdapter(new IoAdapter(app));

  // Strips unknown fields and 400s on anything that fails a DTO's
  // class-validator decorators — every controller in this API relies on
  // this running globally rather than validating manually per route.
  app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true, forbidNonWhitelisted: true }));
  app.useGlobalFilters(new HttpExceptionFilter());

  const origins = config.get<string>('CORS_ORIGINS', 'http://localhost:8765').split(',').map((o) => o.trim());
  app.enableCors({ origin: origins, credentials: true });

  app.setGlobalPrefix('api');

  const port = config.get<number>('PORT', 3000);
  await app.listen(port, '0.0.0.0');
  Logger.log(`HomeServant API listening on :${port}`, 'Bootstrap');
}

bootstrap();
