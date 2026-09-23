import { IsString, Length } from 'class-validator';

export class UpdateBankDetailsDto {
  @IsString()
  bankCode!: string;

  /// Nigerian NUBAN account numbers are always 10 digits.
  @IsString()
  @Length(10, 10)
  accountNumber!: string;
}
