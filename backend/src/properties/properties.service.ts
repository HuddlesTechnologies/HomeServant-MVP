import { ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { CreatePropertyDto } from './dto/create-property.dto';
import { QueryPropertiesDto } from './dto/query-properties.dto';
import { UpdatePropertyDto } from './dto/update-property.dto';

@Injectable()
export class PropertiesService {
  constructor(private readonly prisma: PrismaService) {}

  async findMany(query: QueryPropertiesDto) {
    const where: Prisma.PropertyWhereInput = {
      state: query.state,
      category: query.category,
      landlordId: query.landlordId,
      isOccupied: query.isOccupied === undefined ? undefined : query.isOccupied === 'true',
      price: {
        gte: query.minPrice,
        lte: query.maxPrice,
      },
    };

    const page = query.page ?? 1;
    const pageSize = query.pageSize ?? 20;

    const [items, total] = await Promise.all([
      this.prisma.property.findMany({
        where,
        include: { landlord: { select: { id: true, fullName: true } } },
        orderBy: { createdAt: 'desc' },
        skip: (page - 1) * pageSize,
        take: pageSize,
      }),
      this.prisma.property.count({ where }),
    ]);

    return { items, total, page, pageSize };
  }

  async findOne(id: string) {
    const property = await this.prisma.property.findUnique({
      where: { id },
      include: { landlord: { select: { id: true, fullName: true } } },
    });
    if (!property) throw new NotFoundException('Property not found');
    return property;
  }

  create(landlordId: string, dto: CreatePropertyDto) {
    return this.prisma.property.create({ data: { ...dto, landlordId } });
  }

  async update(id: string, landlordId: string, dto: UpdatePropertyDto) {
    await this.assertOwnership(id, landlordId);
    return this.prisma.property.update({ where: { id }, data: dto });
  }

  async remove(id: string, landlordId: string): Promise<void> {
    await this.assertOwnership(id, landlordId);
    await this.prisma.property.delete({ where: { id } });
  }

  private async assertOwnership(id: string, landlordId: string): Promise<void> {
    const property = await this.prisma.property.findUnique({ where: { id }, select: { landlordId: true } });
    if (!property) throw new NotFoundException('Property not found');
    if (property.landlordId !== landlordId) {
      throw new ForbiddenException('You do not own this property');
    }
  }
}
