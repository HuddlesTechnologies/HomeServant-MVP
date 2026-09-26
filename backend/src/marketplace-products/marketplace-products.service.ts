import { BadRequestException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { StorageService } from '../storage/storage.service';
import { VendorsService } from '../vendors/vendors.service';
import { CreateProductDto } from './dto/create-product.dto';
import { QueryProductsDto } from './dto/query-products.dto';
import { UpdateProductDto } from './dto/update-product.dto';

const vendorSelect = { id: true, businessName: true, state: true, logoUrl: true } as const;

@Injectable()
export class MarketplaceProductsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly vendors: VendorsService,
    private readonly storage: StorageService,
  ) {}

  /// Public catalog — only what a shopper should see: available products
  /// from shops that haven't been deactivated and have passed admin
  /// review (see VendorApplicationStatus — a newly-signed-up vendor can
  /// set up their shop immediately, but nothing they list is publicly
  /// visible until an admin approves them).
  async findMany(query: QueryProductsDto) {
    const where: Prisma.ProductWhereInput = {
      isAvailable: true,
      vendor: { isActive: true, suspendedAt: null, status: 'APPROVED' },
      category: query.category,
      vendorId: query.vendorId,
      ...(query.search
        ? {
            OR: [
              { name: { contains: query.search, mode: 'insensitive' } },
              { vendor: { businessName: { contains: query.search, mode: 'insensitive' } } },
            ],
          }
        : {}),
    };

    const page = query.page ?? 1;
    const pageSize = query.pageSize ?? 20;

    const [items, total] = await Promise.all([
      this.prisma.product.findMany({
        where,
        include: { vendor: { select: vendorSelect } },
        orderBy: { createdAt: 'desc' },
        skip: (page - 1) * pageSize,
        take: pageSize,
      }),
      this.prisma.product.count({ where }),
    ]);

    return { items, total, page, pageSize };
  }

  async findOne(id: string) {
    const product = await this.prisma.product.findUnique({
      where: { id },
      include: { vendor: { select: vendorSelect } },
    });
    if (!product) throw new NotFoundException('Product not found');
    return product;
  }

  async findMine(userId: string) {
    const vendor = await this.vendors.requireOwn(userId);
    return this.prisma.product.findMany({ where: { vendorId: vendor.id }, orderBy: { createdAt: 'desc' } });
  }

  /// Server-side payout gate: a vendor with no bank account on file can't
  /// list a product at all, since there'd be nowhere for a buyer's escrowed
  /// payment to eventually release to. Mirrors the same gate on
  /// PropertiesService.create.
  async create(userId: string, dto: CreateProductDto) {
    await this.storage.assertAreOwnImages(dto.imageUrls);
    const vendor = await this.vendors.requireOwn(userId);
    if (!vendor.bankCode || !vendor.accountNumber) {
      throw new BadRequestException('Please add your Payout Account details in Settings');
    }
    return this.prisma.product.create({ data: { ...dto, vendorId: vendor.id } });
  }

  async update(userId: string, id: string, dto: UpdateProductDto) {
    if (dto.imageUrls) await this.storage.assertAreOwnImages(dto.imageUrls);
    const vendor = await this.vendors.requireOwn(userId);
    await this.assertOwnership(id, vendor.id);
    return this.prisma.product.update({ where: { id }, data: dto });
  }

  /// Soft delete — "Delete" in the vendor's "My Products" screen. A hard
  /// delete would orphan any past MarketplaceOrderItem referencing it.
  async remove(userId: string, id: string): Promise<void> {
    const vendor = await this.vendors.requireOwn(userId);
    await this.assertOwnership(id, vendor.id);
    await this.prisma.product.update({ where: { id }, data: { isAvailable: false } });
  }

  private async assertOwnership(id: string, vendorId: string): Promise<void> {
    const product = await this.prisma.product.findUnique({ where: { id }, select: { vendorId: true } });
    if (!product) throw new NotFoundException('Product not found');
    if (product.vendorId !== vendorId) {
      throw new ForbiddenException('You do not own this product');
    }
  }
}
