import { IsIn, IsString, MinLength } from 'class-validator';

/// Folder is restricted to a known set rather than free text — it becomes
/// part of the storage path, so an arbitrary value would let a caller
/// write outside the buckets this API expects to manage.
const UPLOAD_FOLDERS = ['properties', 'profile-photos', 'marketplace-products', 'vendor-logos'] as const;
export type UploadFolder = (typeof UPLOAD_FOLDERS)[number];

export class CreateSignedUploadUrlDto {
  @IsString()
  @MinLength(1)
  fileName!: string;

  @IsIn(UPLOAD_FOLDERS)
  folder!: UploadFolder;
}
