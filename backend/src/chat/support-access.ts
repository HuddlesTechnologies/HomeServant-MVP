import { PrismaService } from '../prisma/prisma.service';

/// Whether [adminId] — an ADMIN who is *not* a participant of this thread —
/// may read it or act on it. Only support threads are ever open to
/// non-participant admins, and only while nobody has claimed them (the
/// shared Support Queue). Once another admin is handling one, it's theirs:
/// only a SUPER_ADMIN can still see into it. Shared by ChatService (REST)
/// and ChatGateway (socket room joins) so the two can't drift apart.
export async function adminCanAccessSupportThread(
  prisma: PrismaService,
  thread: { isSupport: boolean; assignedAdminId: string | null },
  adminId: string,
): Promise<boolean> {
  if (!thread.isSupport) return false;
  if (!thread.assignedAdminId || thread.assignedAdminId === adminId) return true;
  const admin = await prisma.user.findUnique({ where: { id: adminId }, select: { adminLevel: true } });
  return admin?.adminLevel === 'SUPER_ADMIN';
}
