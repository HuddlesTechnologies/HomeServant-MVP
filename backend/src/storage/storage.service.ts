import { Injectable } from '@nestjs/common';
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

  constructor(private readonly config: ConfigService) {
    this.client = createClient(
      this.config.getOrThrow<string>('SUPABASE_URL'),
      this.config.getOrThrow<string>('SUPABASE_SERVICE_ROLE_KEY'),
    );
    this.bucket = this.config.get<string>('SUPABASE_STORAGE_BUCKET', 'homeservant-uploads');
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
}
