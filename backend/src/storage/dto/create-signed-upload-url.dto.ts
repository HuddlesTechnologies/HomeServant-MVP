import { IsIn, IsString, Matches, MinLength } from 'class-validator';

/// Folder is restricted to a known set rather than free text — it becomes
/// part of the storage path, so an arbitrary value would let a caller
/// write outside the buckets this API expects to manage.
const UPLOAD_FOLDERS = ['properties', 'profile-photos', 'marketplace-products', 'vendor-logos', 'chat', 'property-videos'] as const;
export type UploadFolder = (typeof UPLOAD_FOLDERS)[number];

/// Every current UPLOAD_FOLDERS entry is a photo — the signed URL lets the
/// client PUT arbitrary bytes straight to Supabase Storage with no size or
/// content-type check on our side, so this extension allow-list is the one
/// gate we have against someone hosting an HTML/SVG/script file (stored-XSS
/// via the public bucket URL) or another unexpected file type under it.
const IMAGE_EXTENSIONS = /\.(jpe?g|png|webp|heic|heif|gif)$/i;

/// The one exception: a listing's walkthrough video, in its own folder that
/// takes nothing but video files (and no other folder takes video).
const VIDEO_EXTENSIONS = /\.(mp4|mov|m4v|webm)$/i;
const ALLOWED_EXTENSIONS = /\.(jpe?g|png|webp|heic|heif|gif|mp4|mov|m4v|webm)$/i;

/// True when [fileName] is the right kind of file for [folder].
export function extensionFitsFolder(fileName: string, folder: string): boolean {
  return folder === 'property-videos' ? VIDEO_EXTENSIONS.test(fileName) : IMAGE_EXTENSIONS.test(fileName);
}

export class CreateSignedUploadUrlDto {
  @IsString()
  @MinLength(1)
  @Matches(ALLOWED_EXTENSIONS, { message: 'fileName must end in a supported image (jpg, jpeg, png, webp, heic, heif, gif) or video (mp4, mov, m4v, webm) extension' })
  fileName!: string;

  @IsIn(UPLOAD_FOLDERS)
  folder!: UploadFolder;
}
