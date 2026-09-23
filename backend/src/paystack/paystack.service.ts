import { BadRequestException, Injectable, InternalServerErrorException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

export interface PaystackBank {
  name: string;
  code: string;
}

/// Wraps the handful of Paystack "Miscellaneous"/"Verification" endpoints
/// used to let a landlord pick a real Nigerian bank and prove they own the
/// account number they're entering, without this app having to maintain
/// its own bank list or do account-name lookups itself.
@Injectable()
export class PaystackService {
  private readonly secretKey: string;
  private banksCache: { banks: PaystackBank[]; fetchedAt: number } | null = null;
  private static readonly BANKS_CACHE_TTL_MS = 24 * 60 * 60 * 1000;

  constructor(private readonly config: ConfigService) {
    this.secretKey = this.config.getOrThrow<string>('PAYSTACK_SECRET_KEY');
  }

  /// Nigerian banks Paystack can resolve accounts against — cached in
  /// memory since this list changes rarely, so a landlord opening the bank
  /// picker doesn't cost a Paystack call every time.
  async listBanks(): Promise<PaystackBank[]> {
    const cached = this.banksCache;
    if (cached && Date.now() - cached.fetchedAt < PaystackService.BANKS_CACHE_TTL_MS) {
      return cached.banks;
    }

    const response = await fetch('https://api.paystack.co/bank?country=nigeria&currency=NGN', {
      headers: { Authorization: `Bearer ${this.secretKey}` },
    });
    const body = (await response.json()) as { status: boolean; message: string; data?: { name: string; code: string; active: boolean }[] };
    if (!response.ok || !body.status || !body.data) {
      throw new InternalServerErrorException('Could not load the bank list right now');
    }

    const banks = body.data.filter((b) => b.active).map((b) => ({ name: b.name, code: b.code }));
    this.banksCache = { banks, fetchedAt: Date.now() };
    return banks;
  }

  /// Resolves an account number + bank code to the account holder's name
  /// as it exists at the bank — this is what a landlord's `accountName`
  /// gets set from (see UsersService.updateBankDetails), never from
  /// anything the client claims directly.
  async resolveAccount(accountNumber: string, bankCode: string): Promise<{ accountNumber: string; accountName: string }> {
    const response = await fetch(
      `https://api.paystack.co/bank/resolve?account_number=${encodeURIComponent(accountNumber)}&bank_code=${encodeURIComponent(bankCode)}`,
      { headers: { Authorization: `Bearer ${this.secretKey}` } },
    );
    const body = (await response.json()) as { status: boolean; message: string; data?: { account_number: string; account_name: string } };
    if (!response.ok || !body.status || !body.data) {
      throw new BadRequestException(body.message || "Couldn't verify that account number — check the bank and number are correct");
    }
    return { accountNumber: body.data.account_number, accountName: body.data.account_name };
  }
}
