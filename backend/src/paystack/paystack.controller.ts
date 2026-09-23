import { BadRequestException, Controller, Get, Query, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { PaystackService } from './paystack.service';

@Controller('paystack')
@UseGuards(JwtAuthGuard)
export class PaystackController {
  constructor(private readonly paystack: PaystackService) {}

  @Get('banks')
  listBanks() {
    return this.paystack.listBanks();
  }

  @Get('resolve-account')
  resolveAccount(@Query('accountNumber') accountNumber?: string, @Query('bankCode') bankCode?: string) {
    if (!accountNumber || !bankCode) {
      throw new BadRequestException('accountNumber and bankCode are required');
    }
    return this.paystack.resolveAccount(accountNumber, bankCode);
  }
}
