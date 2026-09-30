import { Logger } from '@nestjs/common';
import { NotificationType } from '@prisma/client';
import { ChatService } from '../chat/chat.service';
import { escapeHtml } from '../common/escape-html';
import { EmailProperty, propertyEmailDetails } from '../common/property-email';
import { MailService } from '../mail/mail.service';
import { NotificationsService } from '../notifications/notifications.service';

/// How the payment flows tell people what happened: an in-app notification
/// plus an email, and a notice in the tenant–landlord chat. These run after
/// the money has moved, so none of them can undo or block it.
export class PaymentNotices {
  constructor(
    private readonly notifications: NotificationsService,
    private readonly mail: MailService,
    private readonly chat: ChatService,
    private readonly logger: Logger,
  ) {}

  /// In-app notification, plus an email when [email] is given (callers
  /// that only have a user id skip the email rather than look it up).
  /// A booking's emails include [property]'s details so it's clear which
  /// listing they're about. MailService never throws.
  async notifyBoth(
    userId: string,
    email: string | undefined,
    type: NotificationType,
    title: string,
    body: string,
    threadId?: string,
    property?: EmailProperty,
  ): Promise<void> {
    await this.notifications.create(userId, type, title, body, threadId);
    if (email) {
      const details = property ? propertyEmailDetails(property) : null;
      await this.mail.send(email, title, `<p>${escapeHtml(body)}</p>${details?.html ?? ''}`, body + (details?.text ?? ''));
    }
  }

  /// [notifyBoth] for a booking, with the property's details in the email.
  notifyAboutBooking(
    booking: { property: EmailProperty },
    userId: string,
    email: string | undefined,
    type: NotificationType,
    title: string,
    body: string,
    threadId?: string,
  ): Promise<void> {
    return this.notifyBoth(userId, email, type, title, body, threadId, booking.property);
  }

  /// Posts [body] as a system notice in the booking's tenant–landlord chat,
  /// starting the chat first when [createIfMissing]. Returns the thread id
  /// (so a notification can open it), or null if there's no chat or
  /// posting failed; a failure is logged, never thrown.
  async postBookingSystemMessage(
    booking: { tenantId: string; propertyId: string; property: { landlordId: string } },
    body: string,
    createIfMissing: boolean,
  ): Promise<string | null> {
    try {
      return await this.chat.postBookingSystemMessage({
        tenantId: booking.tenantId,
        landlordId: booking.property.landlordId,
        propertyId: booking.propertyId,
        body,
        createIfMissing,
      });
    } catch (err) {
      this.logger.error(`Couldn't post the booking system message: ${err}`);
      return null;
    }
  }
}
