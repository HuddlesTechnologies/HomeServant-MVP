import { IsString, MinLength } from 'class-validator';

export class SetUserPasswordDto {
  @IsString()
  @MinLength(8, { message: 'Password must be at least 8 characters' })
  newPassword!: string;

  @IsString()
  @MinLength(10, { message: 'Give a bit more detail (at least 10 characters) — this is recorded in the admin activity log' })
  reason!: string;
}
