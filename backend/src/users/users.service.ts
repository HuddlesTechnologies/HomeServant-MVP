import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { UpdateProfileDto } from './dto/update-profile.dto';

@Injectable()
export class UsersService {
  constructor(private readonly prisma: PrismaService) {}

  async findById(id: string) {
    const user = await this.prisma.user.findUnique({
      where: { id },
      select: {
        id: true,
        email: true,
        role: true,
        firstName: true,
        lastName: true,
        fullName: true,
        phoneNumber: true,
        houseAddress: true,
        dateOfBirth: true,
        profilePhotoUrl: true,
        twoFactorEnabled: true,
        createdAt: true,
      },
    });
    if (!user) throw new NotFoundException('User not found');
    return user;
  }

  async updateProfile(id: string, dto: UpdateProfileDto) {
    return this.prisma.user.update({
      where: { id },
      data: { ...dto, dateOfBirth: dto.dateOfBirth ? new Date(dto.dateOfBirth) : undefined },
      select: {
        id: true,
        email: true,
        role: true,
        firstName: true,
        lastName: true,
        fullName: true,
        phoneNumber: true,
        houseAddress: true,
        dateOfBirth: true,
        profilePhotoUrl: true,
        twoFactorEnabled: true,
      },
    });
  }
}
