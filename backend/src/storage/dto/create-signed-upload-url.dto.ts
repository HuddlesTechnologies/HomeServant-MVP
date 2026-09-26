import { IsIn, IsString, Matches, MinLength } from 'class-validator';

/// Folder is restricted to a known set rather than free text — it becomes
/// part of the storage path, so an arbitrary value would let a caller
/// write outside the buckets this API expects to manage.
const UPLOAD_FOLDERS = ['properties', 'profile-photos', 'marketplace-products', 'vendor-logos', 'chat'] as const;
export type UploadFolder = (typeof UPLOAD_FOLDERS)[number];

/// Every current UPLOAD_FOLDERS entry is a photo — the signed URL lets the
/// client PUT arbitrary bytes straight to Supabase Storage with no size or
/// content-type check on our side, so this extension allow-list is the one
/// gate we have against someone hosting an HTML/SVG/script file (stored-XSS
/// via the public bucket URL) or another unexpected file type under it.
const ALLOWED_EXTENSIONS = /\.(jpe?g|png|webp|heic|heif|gif)$/i;

export class CreateSignedUploadUrlDto {
  @IsString()
  @MinLength(1)
  @Matches(ALLOWED_EXTENSIONS, { message: 'fileName must end in a supported image extension (jpg, jpeg, png, webp, heic, heif, gif)' })
  fileName!: string;

  @IsIn(UPLOAD_FOLDERS)
  folder!: UploadFolder;
}
