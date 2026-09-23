import { IsBoolean } from 'class-validator';

export class RespondBookingDto {
  @IsBoolean()
  accepted!: boolean;
}
