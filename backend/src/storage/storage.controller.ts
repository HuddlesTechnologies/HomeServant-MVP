import { Body, Controller, Post, UseGuards } from '@nestjs/common';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { AuthenticatedUser } from '../auth/strategies/jwt.strategy';
import { CreateSignedUploadUrlDto } from './dto/create-signed-upload-url.dto';
import { StorageService } from './storage.service';

@Controller('uploads')
@UseGuards(JwtAuthGuard)
export class StorageController {
  constructor(private readonly storage: StorageService) {}

  /// Client PUTs the file bytes straight to `signedUrl`, then stores
  /// `publicUrl` on the property/profile record — this API never sees
  /// the file itself.
  @Post('sign')
  signUploadUrl(@Body() dto: CreateSignedUploadUrlDto, @CurrentUser() user: AuthenticatedUser) {
    return this.storage.createSignedUploadUrl(user.sub, dto.fileName, dto.folder);
  }
}
