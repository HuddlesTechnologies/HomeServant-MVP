import { Body, Controller, Get, HttpCode, HttpStatus, Param, Patch, Post, Query, UseGuards } from '@nestjs/common';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { AuthenticatedUser } from '../auth/strategies/jwt.strategy';
import { ChatGateway } from './chat.gateway';
import { ChatService } from './chat.service';
import { CreateThreadDto } from './dto/create-thread.dto';
import { SendMessageDto } from './dto/send-message.dto';

@Controller('threads')
@UseGuards(JwtAuthGuard)
export class ChatController {
  constructor(
    private readonly chat: ChatService,
    private readonly gateway: ChatGateway,
  ) {}

  @Get()
  mine(@CurrentUser() user: AuthenticatedUser) {
    return this.chat.findForUser(user.sub);
  }

  @Post()
  open(@CurrentUser() user: AuthenticatedUser, @Body() dto: CreateThreadDto) {
    return this.chat.findOrCreateThread(user.sub, dto);
  }

  @Get(':id/messages')
  messages(@Param('id') id: string, @CurrentUser() user: AuthenticatedUser, @Query('before') before?: string) {
    return this.chat.findMessages(id, user.sub, before);
  }

  @Post(':id/messages')
  async send(@Param('id') id: string, @CurrentUser() user: AuthenticatedUser, @Body() dto: SendMessageDto) {
    const message = await this.chat.sendMessage(id, user.sub, dto);
    const participantIds = await this.chat.participantIds(id);
    this.gateway.broadcastMessage(participantIds, user.sub, id, message);
    return message;
  }

  @Patch(':id/read')
  @HttpCode(HttpStatus.NO_CONTENT)
  async markRead(@Param('id') id: string, @CurrentUser() user: AuthenticatedUser): Promise<void> {
    await this.chat.markRead(id, user.sub);
  }
}
