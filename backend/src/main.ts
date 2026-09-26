import { Logger, ValidationPipe } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { NestFactory } from '@nestjs/core';
import { IoAdapter } from '@nestjs/platform-socket.io';
import compression from 'compression';
import helmet from 'helmet';
import { AppModule } from './app.module';
import { HttpExceptionFilter } from './common/filters/http-exception.filter';

async function bootstrap() {
  // rawBody: true makes Nest's body-parser stash the untouched request
  // bytes on `req.rawBody` for every route, alongside the normal parsed
  // `req.body` — needed only by PaystackController's webhook, which must
  // HMAC the exact bytes Paystack signed (re-serializing the parsed JSON
  // can produce different bytes and break the signature check). Every
  // other route is unaffected; it just also gets a rawBody it ignores.
  const app = await NestFactory.create(AppModule, { rawBody: true });
  app.use(helmet());
  app.use(compression());
  const config = app.get(ConfigService);
  // Render sits in front of this container as a reverse proxy — without
  // this, `req.ip` is the proxy's own address for every request, which
  // is useless for the admin console's Activity Log (login IP/location).
  app.getHttpAdapter().getInstance().set('trust proxy', 1);
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
