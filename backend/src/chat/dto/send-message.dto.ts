import { IsOptional, IsString } from 'class-validator';

/// [body] is now optional — an image message can be sent with no caption
/// at all. ChatService.sendMessage is what actually requires at least one
/// of [body]/[attachmentUrl] to be present; class-validator has no clean
/// "at least one of these two" decorator, so that check lives there
/// instead of here.
export class SendMessageDto {
  @IsOptional()
  @IsString()
  body?: string;

  /// A Supabase Storage public URL from `POST /uploads/sign` (folder:
  /// 'chat') — re-verified by ChatService.sendMessage via
  /// StorageService.assertIsOwnImage before being trusted, same as every
  /// other client-supplied image URL in this app.
  @IsOptional()
  @IsString()
  attachmentUrl?: string;
}
