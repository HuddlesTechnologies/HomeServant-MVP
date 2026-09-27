import { SupportPriority, SupportTopic } from '@prisma/client';
import { IsEnum, IsOptional, IsString, MaxLength, MinLength } from 'class-validator';

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
