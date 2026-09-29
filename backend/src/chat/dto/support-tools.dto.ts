import { SupportPriority, SupportTopic } from '@prisma/client';
import { IsEnum, IsInt, IsOptional, IsString, Max, MaxLength, Min, MinLength } from 'class-validator';

export class OpenSupportThreadDto {
  @IsOptional()
  @IsEnum(SupportTopic)
  topic?: SupportTopic;
}

export class CreateSupportNoteDto {
  @IsString()
  @MinLength(1)
  @MaxLength(2000)
  body!: string;
}

export class TriageThreadDto {
  @IsOptional()
  @IsEnum(SupportTopic)
  topic?: SupportTopic;

  @IsOptional()
  @IsEnum(SupportPriority)
  priority?: SupportPriority;
}

export class SavedReplyDto {
  @IsString()
  @MinLength(1)
  @MaxLength(80)
  title!: string;

  @IsString()
  @MinLength(1)
  @MaxLength(2000)
  body!: string;
}

export class RateSupportThreadDto {
  @IsInt()
  @Min(1)
  @Max(5)
  rating!: number;

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  comment?: string;
}

export class LogCallDto {
  @IsString()
  @MinLength(10, { message: 'Give a bit more detail (at least 10 characters) — the reason is logged with this chat' })
  @MaxLength(500)
  reason!: string;
}
