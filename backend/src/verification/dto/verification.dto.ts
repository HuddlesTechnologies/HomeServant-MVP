import { IdType } from '@prisma/client';
import { IsEnum, IsIn, IsOptional, IsString, Matches, MaxLength, MinLength } from 'class-validator';

/// Photos or a PDF — identity documents are often scanned PDFs.
const DOCUMENT_EXTENSIONS = /\.(jpe?g|png|webp|heic|heif|pdf)$/i;

export class SignVerificationUploadDto {
  @IsString()
  @MinLength(1)
  @Matches(DOCUMENT_EXTENSIONS, { message: 'Upload a photo (jpg, png, webp, heic) or a PDF' })
  fileName!: string;
}

export class UpdateVerificationDto {
  @IsOptional()
  @IsEnum(IdType)
  idType?: IdType;

  @IsOptional()
  @IsString()
  @MaxLength(30)
  idNumber?: string;

  @IsOptional()
  @IsString()
  @MaxLength(300)
  certificatePath?: string;

  @IsOptional()
  @IsString()
  @MaxLength(300)
  documentPath?: string;
}

export class ReviewVerificationDto {
  @IsIn(['APPROVE', 'REJECT'])
  decision!: 'APPROVE' | 'REJECT';

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  note?: string;
}
