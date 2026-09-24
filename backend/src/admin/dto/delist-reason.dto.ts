import { IsString, MinLength } from 'class-validator';

export class DelistReasonDto {
  @IsString()
  @MinLength(10, { message: 'Give a bit more detail (at least 10 characters) — this is emailed to the user' })
  reason!: string;
}
