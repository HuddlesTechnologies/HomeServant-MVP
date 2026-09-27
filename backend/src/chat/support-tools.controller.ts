import { Body, Controller, Delete, Get, HttpCode, HttpStatus, Param, Patch, Post, UseGuards } from '@nestjs/common';
import { UserRole } from '@prisma/client';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { Roles } from '../common/decorators/roles.decorator';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { AuthenticatedUser } from '../auth/strategies/jwt.strategy';
import { CreateSupportNoteDto, SavedReplyDto, TriageThreadDto } from './dto/support-tools.dto';
import { SupportToolsService } from './support-tools.service';

/// Admin-only support tools — see SupportToolsService.
@Controller()
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.ADMIN)
export class SupportToolsController {
  constructor(private readonly tools: SupportToolsService) {}

  @Get('threads/:id/notes')
  notes(@Param('id') id: string, @CurrentUser() user: AuthenticatedUser) {
    return this.tools.listNotes(id, user.sub);
  }

  @Post('threads/:id/notes')
  addNote(@Param('id') id: string, @CurrentUser() user: AuthenticatedUser, @Body() dto: CreateSupportNoteDto) {
    return this.tools.addNote(id, user.sub, dto.body);
  }

  @Patch('threads/:id/triage')
  triage(@Param('id') id: string, @CurrentUser() user: AuthenticatedUser, @Body() dto: TriageThreadDto) {
    return this.tools.triage(id, user.sub, dto.topic, dto.priority);
  }

  @Get('threads/:id/customer-context')
  customerContext(@Param('id') id: string, @CurrentUser() user: AuthenticatedUser) {
    return this.tools.customerContext(id, user.sub);
  }

  @Get('support/saved-replies')
  savedReplies() {
    return this.tools.listSavedReplies();
  }

  @Post('support/saved-replies')
  createSavedReply(@CurrentUser() user: AuthenticatedUser, @Body() dto: SavedReplyDto) {
    return this.tools.createSavedReply(user.sub, dto.title, dto.body);
  }

  @Patch('support/saved-replies/:id')
  updateSavedReply(@Param('id') id: string, @CurrentUser() user: AuthenticatedUser, @Body() dto: SavedReplyDto) {
    return this.tools.updateSavedReply(id, user.sub, dto.title, dto.body);
  }

  @Delete('support/saved-replies/:id')
  @HttpCode(HttpStatus.NO_CONTENT)
  deleteSavedReply(@Param('id') id: string, @CurrentUser() user: AuthenticatedUser) {
    return this.tools.deleteSavedReply(id, user.sub);
  }

  @Get('support/admins')
  transferTargets() {
    return this.tools.transferTargets();
  }
}
