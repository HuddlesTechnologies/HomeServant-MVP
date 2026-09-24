import { IsUUID } from 'class-validator';

export class TransferThreadDto {
  @IsUUID()
  adminId!: string;
}
