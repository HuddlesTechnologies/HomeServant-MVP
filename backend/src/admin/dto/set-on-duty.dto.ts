import { IsBoolean } from 'class-validator';

export class SetOnDutyDto {
  @IsBoolean()
  onDuty!: boolean;
}
