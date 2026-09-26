import { BadRequestException, Injectable } from '@nestjs/common';
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
export class StorageService {
  private readonly client: SupabaseClient;
  private readonly bucket: string;

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

    const probe = '__prefix_probe__';
    const { publicUrl } = this.client.storage.from(this.bucket).getPublicUrl(probe).data;
    this.publicUrlPrefix = publicUrl.slice(0, publicUrl.length - probe.length);
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

  /// Verifies every URL in [urls] via [assertIsOwnImage] — used for the
  /// gallery/multi-photo fields (property galleryUrls, product imageUrls).
  async assertAreOwnImages(urls: string[]): Promise<void> {
    await Promise.all(urls.map((url) => this.assertIsOwnImage(url)));
  }
}
