import { Body, Controller, Delete, Get, HttpCode, HttpStatus, Post, UseGuards } from '@nestjs/common';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { AuthenticatedUser } from '../auth/strategies/jwt.strategy';
import { PushSubscriptionDto, PushUnsubscribeDto } from './dto/push-subscription.dto';
import { PushService } from './push.service';

@Controller('push')
@UseGuards(JwtAuthGuard)
export class PushController {
  constructor(private readonly push: PushService) {}

  /// null when push isn't configured on this server — the client then
  /// doesn't offer it.
  @Get('public-key')
  publicKey() {
    return { publicKey: this.push.publicKey };
  }

  @Post('subscriptions')
  @HttpCode(HttpStatus.NO_CONTENT)
  async subscribe(@CurrentUser() user: AuthenticatedUser, @Body() dto: PushSubscriptionDto): Promise<void> {
    await this.push.subscribe(user.sub, dto.endpoint, dto.keys.p256dh, dto.keys.auth);
  }

  @Delete('subscriptions')
  @HttpCode(HttpStatus.NO_CONTENT)
  async unsubscribe(@CurrentUser() user: AuthenticatedUser, @Body() dto: PushUnsubscribeDto): Promise<void> {
    await this.push.unsubscribe(user.sub, dto.endpoint);
  }
}
