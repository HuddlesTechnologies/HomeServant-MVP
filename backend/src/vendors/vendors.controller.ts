import { Body, Controller, Get, Patch, Post, UseGuards } from '@nestjs/common';
import { UserRole } from '@prisma/client';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { Roles } from '../common/decorators/roles.decorator';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { AuthenticatedUser } from '../auth/strategies/jwt.strategy';
import { CreateVendorProfileDto } from './dto/create-vendor-profile.dto';
import { UpdateVendorProfileDto } from './dto/update-vendor-profile.dto';
import { VendorsService } from './vendors.service';

@Controller('vendors')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.TENANT, UserRole.VENDOR)
export class VendorsController {
  constructor(private readonly vendors: VendorsService) {}

  @Post('me')
  create(@CurrentUser() user: AuthenticatedUser, @Body() dto: CreateVendorProfileDto) {
    return this.vendors.create(user.sub, dto);
  }

  @Get('me')
  findMine(@CurrentUser() user: AuthenticatedUser) {
    return this.vendors.findMine(user.sub);
  }

  @Patch('me')
  update(@CurrentUser() user: AuthenticatedUser, @Body() dto: UpdateVendorProfileDto) {
    return this.vendors.update(user.sub, dto);
  }
}
