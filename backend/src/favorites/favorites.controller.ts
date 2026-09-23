import { Controller, Get, Post, Param, UseGuards } from '@nestjs/common';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { AuthenticatedUser } from '../auth/strategies/jwt.strategy';
import { FavoritesService } from './favorites.service';

@Controller('favorites')
@UseGuards(JwtAuthGuard)
export class FavoritesController {
  constructor(private readonly favorites: FavoritesService) {}

  @Get()
  mine(@CurrentUser() user: AuthenticatedUser) {
    return this.favorites.findForUser(user.sub);
  }

  @Post(':propertyId/toggle')
  toggle(@Param('propertyId') propertyId: string, @CurrentUser() user: AuthenticatedUser) {
    return this.favorites.toggle(user.sub, propertyId);
  }
}
