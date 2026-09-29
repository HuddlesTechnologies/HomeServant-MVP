import { IsString, Length } from 'class-validator';

export class ConfirmPaymentDto {
  /// The `reference` Paystack appends to the callback URL.
  @IsString()
  @Length(1, 100)
  reference!: string;
}
