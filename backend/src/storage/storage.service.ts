import { BadRequestException, Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createClient, SupabaseClient } from '@supabase/supabase-js';
import { randomUUID } from 'crypto';

export interface SignedUpload {
  path: string;
  signedUrl: string;
  token: string;
  publicUrl: string;
}

/// Wraps the Supabase Storage client used server-side only (service role
/// key, never sent to the Flutter client). Issues short-lived signed
/// upload URLs so the client can PUT the file bytes directly to Supabase
/// instead of routing them through this API.
@Injectable()
export class StorageService implements OnModuleInit {
  private readonly logger = new Logger('Storage');
  private readonly client: SupabaseClient;
  private readonly bucket: string;

  /// Identity documents (IDs, ownership certificates). NOT public: objects
  /// here are only reachable through short-lived signed URLs minted for
  /// admins, see [signedViewUrl].
  private readonly privateBucket: string;

  /// Every public object URL this bucket serves starts with this — used by
  /// [assertIsOwnImage] to reject anything else. Derived from the SDK's own
  /// [getPublicUrl] rather than hand-built, so it can't drift from whatever
  /// URL shape the installed `@supabase/supabase-js` version actually
  /// produces.
  private readonly publicUrlPrefix: string;

  constructor(private readonly config: ConfigService) {
    this.client = createClient(
      this.config.getOrThrow<string>('SUPABASE_URL'),
      this.config.getOrThrow<string>('SUPABASE_SERVICE_ROLE_KEY'),
    );
    this.bucket = this.config.get<string>('SUPABASE_STORAGE_BUCKET', 'homeservant-uploads');
    this.privateBucket = this.config.get<string>('SUPABASE_PRIVATE_BUCKET', 'homeservant-private');

    const probe = '__prefix_probe__';
    const { publicUrl } = this.client.storage.from(this.bucket).getPublicUrl(probe).data;
    this.publicUrlPrefix = publicUrl.slice(0, publicUrl.length - probe.length);
  }

  /// Creates the private bucket on first boot if it doesn't exist yet, so
  /// no manual Supabase setup is needed. Never public. Runs in the
  /// background: a slow or unreachable Supabase must not hold up startup.
  onModuleInit(): void {
    void this.ensurePrivateBucket();
    void this.checkPublicBucketAccepts();
  }

  /// The public bucket is set up by hand in the Supabase dashboard. A
  /// bucket accepts every file type unless "Allowed MIME types" is set on
  /// it; if it is, it must include everything the app uploads, or those
  /// uploads fail at Supabase. Logs what this bucket would refuse, and its
  /// per-file size limit (the project-wide limit applies on top of it).
  async checkPublicBucketAccepts(): Promise<string[]> {
    try {
      const { data, error } = await this.client.storage.getBucket(this.bucket);
      if (error || !data) throw error ?? new Error('bucket not found');
      const refused = publicBucketRefuses(data.allowed_mime_types);
      if (refused.length > 0) {
        this.logger.error(
          `Bucket "${this.bucket}" only allows ${data.allowed_mime_types!.join(', ')} — uploads of ${refused.join(', ')} will fail. ` +
            'Add them (or clear Allowed MIME types) in Supabase > Storage > bucket settings.',
        );
      } else {
        this.logger.log(`Bucket "${this.bucket}" accepts every file type the app uploads`);
      }
      if (data.file_size_limit) {
        this.logger.log(`Bucket "${this.bucket}" file size limit: ${Math.round(data.file_size_limit / 1024 / 1024)} MB per file`);
      }
      return refused;
    } catch (error) {
      this.logger.error(`Could not check bucket "${this.bucket}": ${(error as Error)?.message}`);
      return [];
    }
  }

  private async ensurePrivateBucket(): Promise<void> {
    try {
      const { data } = await this.client.storage.getBucket(this.privateBucket);
      if (data) {
        if (data.public) this.logger.error(`Bucket "${this.privateBucket}" is PUBLIC — make it private in Supabase; identity documents are stored there`);
        return;
      }
      const { error } = await this.client.storage.createBucket(this.privateBucket, { public: false });
      if (error) throw error;
      this.logger.log(`Created private bucket "${this.privateBucket}"`);
    } catch (error) {
      this.logger.error(`Could not check/create private bucket "${this.privateBucket}": ${(error as Error).message}`);
    }
  }

  /// Signed upload into the private bucket, under `<folder>/<userId>/`.
  /// Returns the object path to save (there is no public URL).
  async createPrivateSignedUploadUrl(userId: string, fileName: string, folder: string): Promise<{ path: string; signedUrl: string; token: string }> {
    const extension = fileName.includes('.') ? fileName.slice(fileName.lastIndexOf('.')).toLowerCase() : '';
    const path = `${folder}/${userId}/${randomUUID()}${extension}`;
    const { data, error } = await this.client.storage.from(this.privateBucket).createSignedUploadUrl(path);
    if (error) throw error;
    return { path, signedUrl: data.signedUrl, token: data.token };
  }

  /// A client-supplied private path must be one this user was issued (their
  /// own folder) and must hold an image or PDF.
  async assertOwnPrivateDocument(userId: string, path: string, folder: string): Promise<void> {
    if (!path.startsWith(`${folder}/${userId}/`) || path.includes('..')) {
      throw new BadRequestException('That file was not uploaded by this account');
    }
    const url = await this.signedViewUrl(path, 60);
    let contentType: string | null = null;
    try {
      const response = await fetch(url, { method: 'HEAD' });
      if (!response.ok) throw new Error(String(response.status));
      contentType = response.headers.get('content-type');
    } catch {
      throw new BadRequestException('The uploaded file could not be found. Please upload it again.');
    }
    if (!contentType || !(contentType.startsWith('image/') || contentType === 'application/pdf')) {
      throw new BadRequestException('Upload a photo or a PDF');
    }
  }

  /// Deletes every private file under `<folder>/<userId>/` — called when
  /// an account is deleted, so identity documents don't outlive it.
  async removePrivateFilesFor(userId: string, folder: string): Promise<void> {
    try {
      const prefix = `${folder}/${userId}`;
      const { data } = await this.client.storage.from(this.privateBucket).list(prefix, { limit: 1000 });
      const paths = (data ?? []).map((f) => `${prefix}/${f.name}`);
      if (paths.length > 0) await this.client.storage.from(this.privateBucket).remove(paths);
    } catch (error) {
      this.logger.error(`Could not delete private files for ${userId}: ${(error as Error).message}`);
    }
  }

  /// A link to a private object that works for [expiresInSeconds] only.
  async signedViewUrl(path: string, expiresInSeconds = 600): Promise<string> {
    const { data, error } = await this.client.storage.from(this.privateBucket).createSignedUrl(path, expiresInSeconds);
    if (error || !data) throw new BadRequestException('Could not open that document');
    return data.signedUrl;
  }

  /// Namespaces uploads under the owning user's id so one user can't
  /// overwrite another's file by guessing its path, then mints a signed
  /// URL that's only valid for a single upload to that path.
  async createSignedUploadUrl(userId: string, fileName: string, folder: string): Promise<SignedUpload> {
    const extension = fileName.includes('.') ? fileName.slice(fileName.lastIndexOf('.')) : '';
    const path = `${folder}/${userId}/${randomUUID()}${extension}`;

    const { data, error } = await this.client.storage.from(this.bucket).createSignedUploadUrl(path);
    if (error) {
      throw error;
    }

    const { data: publicUrlData } = this.client.storage.from(this.bucket).getPublicUrl(path);

    return {
      path,
      signedUrl: data.signedUrl,
      token: data.token,
      publicUrl: publicUrlData.publicUrl,
    };
  }

  /// [CreateSignedUploadUrlDto]'s extension allow-list only constrains the
  /// *filename* the client asked to reserve — the client then PUTs bytes
  /// and a `Content-Type` header straight to Supabase, bypassing this API
  /// entirely, so a `.jpg` path can still end up storing (and being served
  /// back as) `text/html`. Every endpoint that accepts a client-supplied
  /// image URL (profile photo, property/product photos, vendor logo) calls
  /// this before persisting it, to confirm both that the URL is actually
  /// one of our own bucket's objects (never an arbitrary external URL —
  /// otherwise the HEAD request below would be an SSRF primitive) and that
  /// what's actually stored there is image content, not just named like it.
  async assertIsOwnImage(url: string): Promise<void> {
    if (!url.startsWith(this.publicUrlPrefix)) {
      throw new BadRequestException('Image URL must point to a file uploaded through this app');
    }

    let contentType: string | null;
    try {
      const response = await fetch(url, { method: 'HEAD' });
      if (!response.ok) throw new BadRequestException('Uploaded image could not be verified');
      contentType = response.headers.get('content-type');
    } catch (error) {
      if (error instanceof BadRequestException) throw error;
      throw new BadRequestException('Uploaded image could not be verified');
    }

    if (!contentType?.startsWith('image/')) {
      throw new BadRequestException('The uploaded file is not a valid image');
    }
  }

  /// A listing's walkthrough video: same checks as [assertIsOwnImage] (our
  /// own bucket, and what's stored really is the right kind of file), for
  /// video content in the property-videos folder.
  async assertIsOwnVideo(url: string): Promise<void> {
    if (!url.startsWith(this.publicUrlPrefix) || !url.includes('/property-videos/')) {
      throw new BadRequestException('Video URL must point to a video uploaded through this app');
    }
    let contentType: string | null;
    try {
      const response = await fetch(url, { method: 'HEAD' });
      if (!response.ok) throw new BadRequestException('Uploaded video could not be verified');
      contentType = response.headers.get('content-type');
    } catch (error) {
      if (error instanceof BadRequestException) throw error;
      throw new BadRequestException('Uploaded video could not be verified');
    }
    if (!contentType?.startsWith('video/')) {
      throw new BadRequestException('The uploaded file is not a valid video');
    }
  }

  /// Verifies every URL in [urls] via [assertIsOwnImage] — used for the
  /// gallery/multi-photo fields (property galleryUrls, product imageUrls).
  async assertAreOwnImages(urls: string[]): Promise<void> {
    await Promise.all(urls.map((url) => this.assertIsOwnImage(url)));
  }
}

/// Every content type the app uploads to the public bucket: photos
/// everywhere, and walkthrough videos in property-videos.
export const PUBLIC_UPLOAD_MIME_TYPES = [
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/gif',
  'image/heic',
  'image/heif',
  'video/mp4',
  'video/quicktime',
  'video/x-m4v',
  'video/webm',
] as const;

/// Which of [PUBLIC_UPLOAD_MIME_TYPES] a bucket with [allowed] ("Allowed
/// MIME types"; empty or null = everything, entries may be `type/*`) refuses.
export function publicBucketRefuses(allowed: string[] | null | undefined): string[] {
  if (!allowed || allowed.length === 0) return [];
  return PUBLIC_UPLOAD_MIME_TYPES.filter(
    (type) => !allowed.some((a) => a === type || a === '*/*' || (a.endsWith('/*') && type.startsWith(a.slice(0, -1)))),
  );
}
