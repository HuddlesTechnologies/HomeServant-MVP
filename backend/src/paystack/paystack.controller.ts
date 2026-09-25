import {
  BadRequestException,
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Post,
  Query,
  RawBodyRequest,
  Req,
  UnauthorizedException,
  UseGuards,
} from '@nestjs/common';
import { Request } from 'express';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { PaymentsService } from '../payments/payments.service';
import { PaystackService } from './paystack.service';

@Controller('paystack')
export class PaystackController {
  constructor(
    private readonly paystack: PaystackService,
    private readonly payments: PaymentsService,
  ) {}

  @Get('banks')
  @UseGuards(JwtAuthGuard)
  listBanks() {
    return this.paystack.listBanks();
  }

  @Get('resolve-account')
  @UseGuards(JwtAuthGuard)
  resolveAccount(@Query('accountNumber') accountNumber?: string, @Query('bankCode') bankCode?: string) {
    if (!accountNumber || !bankCode) {
      throw new BadRequestException('accountNumber and bankCode are required');
    }
    return this.paystack.resolveAccount(accountNumber, bankCode);
  }

  /// No auth guard — Paystack calls this directly, not an app user.
  /// Authenticity is instead verified via the `x-paystack-signature`
  /// header (HMAC-SHA512 of the *raw* request body, keyed by the secret
  /// key). This requires the raw bytes Paystack actually sent, which is
  /// why main.ts bootstraps Nest with `rawBody: true` — that populates
  /// `req.rawBody` for every route while still letting the normal
  /// body-parser JSON-decode `@Body()` as usual, so nothing else in the
  /// app had to change its body-parsing setup for this one route.
  @Post('webhook')
  @HttpCode(HttpStatus.OK)
  async webhook(@Req() req: RawBodyRequest<Request>, @Body() body: { event?: string; data?: { reference?: string } }) {
    const signature = req.headers['x-paystack-signature'];
    if (!req.rawBody || !this.paystack.verifyWebhookSignature(req.rawBody, signature)) {
      throw new UnauthorizedException('Invalid Paystack signature');
    }

    if (body.event === 'charge.success' && body.data?.reference) {
      await this.payments.handleChargeSuccess(body.data.reference);
    }
    // Every other event (e.g. transfer.success/failed) is acknowledged but
    // not acted on — transfer status isn't polled/reconciled by this app
    // today; initiateTransfer's own synchronous response is what drives
    // Payment.status = RELEASED. Ack with 200 regardless so Paystack
    // doesn't keep retrying delivery of an event this app doesn't need.
    return { received: true };
  }
}
