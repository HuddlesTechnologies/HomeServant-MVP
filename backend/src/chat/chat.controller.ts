import { Body, Controller, Get, HttpCode, HttpStatus, Param, Patch, Post, Query, UseGuards } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { UserRole } from '@prisma/client';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { Roles } from '../common/decorators/roles.decorator';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { AuthenticatedUser } from '../auth/strategies/jwt.strategy';
import { ChatGateway } from './chat.gateway';
import { ChatService } from './chat.service';
import { CreateThreadDto } from './dto/create-thread.dto';
import { SendMessageDto } from './dto/send-message.dto';
import { TransferThreadDto } from './dto/transfer-thread.dto';

@Controller('threads')
@UseGuards(JwtAuthGuard)
export class ChatController {
  constructor(
    private readonly chat: ChatService,
    private readonly gateway: ChatGateway,
  ) {}

  @Get()
  mine(@CurrentUser() user: AuthenticatedUser) {
    return this.chat.findForUser(user.sub, user.role === UserRole.ADMIN);
  }

  @Post()
  open(@CurrentUser() user: AuthenticatedUser, @Body() dto: CreateThreadDto) {
    return this.chat.findOrCreateThread(user.sub, dto);
  }

  /// "Contact Support" — no recipient to pick, unlike [open]. Reuses (or
  /// starts) the calling user's own open support thread; see
  /// ChatService.openSupportThread.
  @Post('support')
  openSupport(@CurrentUser() user: AuthenticatedUser) {
    return this.chat.openSupportThread(user.sub);
  }

  /// The admin console's shared "Support Queue" — every open support
  /// thread, claimed or not, regardless of which admin (if any) is on it.
  @Get('support-queue')
  @UseGuards(RolesGuard)
  @Roles(UserRole.ADMIN)
  supportQueue() {
    return this.chat.findSupportQueue();
  }

  /// Explicitly claims an unattended support thread — fired the moment an
  /// admin opens it from the shared Support Queue, before they've
  /// necessarily replied. See ChatService.claimThread.
  @Patch(':id/claim')
  @HttpCode(HttpStatus.NO_CONTENT)
  @UseGuards(RolesGuard)
  @Roles(UserRole.ADMIN)
  async claim(@Param('id') id: string, @CurrentUser() user: AuthenticatedUser): Promise<void> {
    await this.chat.claimThread(id, user.sub);
  }

  @Get(':id/messages')
  messages(@Param('id') id: string, @CurrentUser() user: AuthenticatedUser, @Query('before') before?: string) {
    return this.chat.findMessages(id, user.sub, user.role, before);
  }

  // Moderate throttling: authenticated but user-generated/spammable — caps
  // message-flooding while staying well above normal chat cadence.
  @Throttle({ default: { limit: 30, ttl: 60000 } })
  @Post(':id/messages')
  async send(@Param('id') id: string, @CurrentUser() user: AuthenticatedUser, @Body() dto: SendMessageDto) {
    const message = await this.chat.sendMessage(id, user.sub, user.role, dto);
    const participantIds = await this.chat.participantIds(id);
    this.gateway.broadcastMessage(participantIds, user.sub, id, message);
    return message;
  }

  @Patch(':id/read')
  @HttpCode(HttpStatus.NO_CONTENT)
  async markRead(@Param('id') id: string, @CurrentUser() user: AuthenticatedUser): Promise<void> {
    await this.chat.markRead(id, user.sub, user.role);
    // Tells the *other* participant's already-open thread screen (if any)
    // that their sent messages were just seen — ChatService.markRead only
    // updates the DB, it has no socket of its own to push through.
    const participantIds = await this.chat.participantIds(id);
    for (const participantId of participantIds) {
      if (participantId === user.sub) continue;
      this.gateway.emitToUser(participantId, 'message:read', { threadId: id });
    }
  }

  /// Admin-only — any admin can resolve a support thread, not just whoever
  /// claimed it (mirrors the shared-queue visibility above).
  @Patch(':id/resolve')
  @HttpCode(HttpStatus.NO_CONTENT)
  @UseGuards(RolesGuard)
  @Roles(UserRole.ADMIN)
  async resolve(@Param('id') id: string, @CurrentUser() user: AuthenticatedUser): Promise<void> {
    await this.chat.resolveSupportThread(id, user.sub);
  }

  /// Admin-only in practice — [transferThread] itself already refuses
  /// unless [user.sub] is a participant and [dto.adminId] is an admin
  /// account, so a non-admin caller would just get refused there too;
  /// no separate `@Roles` needed on top.
  @Patch(':id/transfer')
  @HttpCode(HttpStatus.NO_CONTENT)
  async transfer(@Param('id') id: string, @CurrentUser() user: AuthenticatedUser, @Body() dto: TransferThreadDto): Promise<void> {
    await this.chat.transferThread(id, user.sub, dto.adminId);
  }
}
