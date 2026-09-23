import { IsIn } from 'class-validator';

export class RespondOrderItemDto {
  @IsIn(['COMPLETED', 'CANCELLED'])
  status!: 'COMPLETED' | 'CANCELLED';
}
