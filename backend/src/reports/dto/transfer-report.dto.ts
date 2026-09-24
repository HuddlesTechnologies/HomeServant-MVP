import { IsUUID } from 'class-validator';

export class TransferReportDto {
  @IsUUID()
  adminId!: string;
}
