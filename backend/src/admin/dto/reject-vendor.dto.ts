import { IsOptional, IsString } from 'class-validator';

export class RejectVendorDto {
  @IsOptional()
  @IsString()
  reason?: string;
}
