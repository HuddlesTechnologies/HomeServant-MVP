import { IsDateString } from 'class-validator';

export class ProposeInspectionDto {
  @IsDateString()
  requestedDate!: string;
}
