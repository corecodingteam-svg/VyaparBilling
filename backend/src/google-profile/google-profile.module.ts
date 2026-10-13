import { BadRequestException, Body, Controller, Get, Injectable, Logger, Module, Post, Put, Query, Res, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { IsOptional, IsString, IsUrl, MaxLength, MinLength } from 'class-validator';
import type { Response } from 'express';
import { accessToken, DriveConfig, driveConfig, exchangeCode, signState, verifyState } from '../backups/drive';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { JwtPayload } from '../auth/jwt.strategy';
import { ADMINS, Roles } from '../auth/roles';
import { IntegrationsService } from '../integrations/integrations.service';

const SCOPE = 'https://www.googleapis.com/auth/business.manage https://www.googleapis.com/auth/userinfo.email';
const ACCOUNTS = 'https://mybusinessaccountmanagement.googleapis.com/v1';
const INFO = 'https://mybusinessbusinessinformation.googleapis.com/v1';
const V4 = 'https://mybusiness.googleapis.com/v4';
const STARS: Record<string, number> = { ONE: 1, TWO: 2, THREE: 3, FOUR: 4, FIVE: 5 };

class SelectDto {
  @IsString() @MinLength(3) @MaxLength(200) account: string;
  @IsString() @MinLength(3) @MaxLength(200) location: string;
  @IsOptional() @IsString() @MaxLength(200) title?: string;
}
class PostDto {
  @IsString() @MinLength(1) @MaxLength(1500) summary: string;
  @IsOptional() @IsUrl() learnMoreUrl?: string;
}
class ReplyDto {
  @IsString() @MinLength(1) @MaxLength(300) reviewId: string;
  @IsString() @MinLength(1) @MaxLength(4000) comment: string;
}
class ProfileDto {
  @IsOptional() @IsString() @MaxLength(750) description?: string;
  @IsOptional() @IsString() @MaxLength(300) website?: string;
}

@Injectable()
export class GoogleProfileService {
  private readonly log = new Logger('GoogleProfile');

  constructor(private readonly integrations: IntegrationsService) {}

  private get secret() {
    return process.env.JWT_SECRET ?? '';
  }

  private config(): DriveConfig {
    const base = driveConfig();
    if (!base) {
      throw new BadRequestException({ code: 'GOOGLE_NOT_CONFIGURED', message: 'Google sign-in is not set up on this server. Ask whoever runs it to add the Google client ID and secret.' });
    }
    return { ...base, redirectUri: `${new URL(base.redirectUri).origin}/api/v1/google-profile/callback` };
  }

  authUrl(firmId: string) {
    const c = this.config();
    return {
      url: 'https://accounts.google.com/o/oauth2/v2/auth?' +
        new URLSearchParams({ client_id: c.clientId, redirect_uri: c.redirectUri, response_type: 'code', scope: SCOPE, access_type: 'offline', prompt: 'consent', state: signState(firmId, this.secret) }),
    };
  }

  /** Google redirects the browser here after consent; returns where to send it next. */
  async callback(code?: string, state?: string, error?: string) {
    const app = (process.env.APP_URL ?? '').replace(/\/$/, '');
    const back = (r: string) => `${app}/#/google-profile?connected=${r}`;
    const firmId = state ? verifyState(state, this.secret) : null;
    if (!firmId || !code || error) return back('failed');
    try {
      const { refreshToken, email } = await exchangeCode(this.config(), code);
      await this.integrations.write(firmId, 'google_profile', email ? { email } : {}, { refreshToken });
      return back('yes');
    } catch (e) {
      this.log.warn(`Google Business Profile connection failed: ${(e as Error).message}`);
      return back('failed');
    }
  }

  private async session(firmId: string) {
    const c = await this.integrations.credentials(firmId, 'google_profile');
    if (!c?.secrets.refreshToken) throw new BadRequestException({ code: 'NOT_CONNECTED', message: 'Google Business Profile is not connected.' });
    return { c, token: await accessToken(this.config(), c.secrets.refreshToken, fetch) };
  }

  private async api(token: string, method: string, url: string, body?: unknown) {
    const res = await fetch(url, {
      method, headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' }, body: body ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(20_000),
    });
    const json: any = await res.json().catch(() => ({}));
    if (!res.ok) throw new BadRequestException({ code: 'GOOGLE_ERROR', message: `Google said: ${json?.error?.message ?? `HTTP ${res.status}`}` });
    return json;
  }

  /** Every business listing the connected Google account manages. */
  async locations(firmId: string) {
    const { token } = await this.session(firmId);
    const accounts = (await this.api(token, 'GET', `${ACCOUNTS}/accounts`)).accounts ?? [];
    const out: { account: string; accountName: string; location: string; title: string; address: string | null }[] = [];
    for (const a of accounts) {
      const r = await this.api(token, 'GET', `${INFO}/${a.name}/locations?readMask=name,title,storefrontAddress&pageSize=100`);
      for (const l of r.locations ?? []) {
        const addr = l.storefrontAddress;
        out.push({
          account: a.name, accountName: a.accountName ?? a.name, location: l.name, title: l.title ?? l.name,
          address: addr ? [...(addr.addressLines ?? []), addr.locality, addr.postalCode].filter(Boolean).join(', ') : null,
        });
      }
    }
    return out;
  }

  async select(firmId: string, dto: SelectDto) {
    const c = await this.integrations.credentials(firmId, 'google_profile');
    if (!c) throw new BadRequestException({ code: 'NOT_CONNECTED', message: 'Google Business Profile is not connected.' });
    await this.integrations.write(firmId, 'google_profile', { ...c.config, accountName: dto.account, locationId: dto.location, locationName: dto.title ?? dto.location }, c.secrets);
  }

  private async chosen(firmId: string) {
    const s = await this.session(firmId);
    const { accountName, locationId } = s.c.config;
    if (!accountName || !locationId) throw new BadRequestException({ code: 'NO_LOCATION', message: 'Choose which business listing to manage first.' });
    // The v4 endpoints name a location as accounts/{a}/locations/{l}; the newer ones as locations/{l}.
    const short = locationId.startsWith('locations/') ? locationId : `locations/${locationId.split('/').pop()}`;
    return { token: s.token, location: short, v4: `${V4}/${accountName}/${short}` };
  }

  async profile(firmId: string) {
    const { token, location } = await this.chosen(firmId);
    const l = await this.api(token, 'GET', `${INFO}/${location}?readMask=name,title,profile,websiteUri,phoneNumbers,storefrontAddress`);
    return { title: l.title, description: l.profile?.description ?? '', website: l.websiteUri ?? '', phone: l.phoneNumbers?.primaryPhone ?? '' };
  }

  async updateProfile(firmId: string, dto: ProfileDto) {
    const { token, location } = await this.chosen(firmId);
    const mask = [dto.description !== undefined && 'profile', dto.website !== undefined && 'websiteUri'].filter(Boolean) as string[];
    if (!mask.length) return this.profile(firmId);
    await this.api(token, 'PATCH', `${INFO}/${location}?updateMask=${mask.join(',')}`, {
      ...(dto.description !== undefined ? { profile: { description: dto.description } } : {}), ...(dto.website !== undefined ? { websiteUri: dto.website } : {}),
    });
    return this.profile(firmId);
  }

  /** A "What's new" post on the listing. */
  async post(firmId: string, dto: PostDto) {
    const { token, v4 } = await this.chosen(firmId);
    const r = await this.api(token, 'POST', `${v4}/localPosts`, {
      languageCode: 'en', summary: dto.summary, topicType: 'STANDARD', ...(dto.learnMoreUrl ? { callToAction: { actionType: 'LEARN_MORE', url: dto.learnMoreUrl } } : {}),
    });
    return { name: r.name, url: r.searchUrl ?? null };
  }

  async reviews(firmId: string) {
    const { token, v4 } = await this.chosen(firmId);
    const r = await this.api(token, 'GET', `${v4}/reviews?pageSize=50&orderBy=updateTime desc`);
    return {
      average: r.averageRating ?? null,
      total: r.totalReviewCount ?? 0,
      reviews: (r.reviews ?? []).map((v: any) => ({
        id: v.reviewId, name: v.reviewer?.displayName ?? 'A customer', stars: STARS[v.starRating] ?? 0, comment: v.comment ?? '', at: v.updateTime, reply: v.reviewReply?.comment ?? null,
      })),
    };
  }

  async reply(firmId: string, reviewId: string, comment: string) {
    const { token, v4 } = await this.chosen(firmId);
    await this.api(token, 'PUT', `${v4}/reviews/${encodeURIComponent(reviewId)}/reply`, { comment });
  }
}

@ApiTags('google-profile')
@Controller('google-profile')
export class GoogleProfileController {
  constructor(private readonly g: GoogleProfileService) {}

  @Get('auth-url')
  @ApiBearerAuth() @UseGuards(JwtAuthGuard) @Roles(...ADMINS)
  authUrl(@CurrentUser() u: JwtPayload) {
    return this.g.authUrl(u.firmId);
  }

  /** Opened by Google in the user's browser, so it carries no login; the signed state says which company. */
  @Get('callback')
  async callback(@Res() res: Response, @Query('code') code?: string, @Query('state') state?: string, @Query('error') error?: string) {
    res.redirect(await this.g.callback(code, state, error));
  }

  @Get('locations')
  @ApiBearerAuth() @UseGuards(JwtAuthGuard) @Roles(...ADMINS)
  locations(@CurrentUser() u: JwtPayload) {
    return this.g.locations(u.firmId);
  }

  @Post('location')
  @ApiBearerAuth() @UseGuards(JwtAuthGuard) @Roles(...ADMINS)
  async select(@CurrentUser() u: JwtPayload, @Body() dto: SelectDto) {
    await this.g.select(u.firmId, dto);
    return { ok: true };
  }

  @Get('profile')
  @ApiBearerAuth() @UseGuards(JwtAuthGuard) @Roles(...ADMINS)
  profile(@CurrentUser() u: JwtPayload) {
    return this.g.profile(u.firmId);
  }

  @Put('profile')
  @ApiBearerAuth() @UseGuards(JwtAuthGuard) @Roles(...ADMINS)
  updateProfile(@CurrentUser() u: JwtPayload, @Body() dto: ProfileDto) {
    return this.g.updateProfile(u.firmId, dto);
  }

  @Post('posts')
  @ApiBearerAuth() @UseGuards(JwtAuthGuard) @Roles(...ADMINS)
  post(@CurrentUser() u: JwtPayload, @Body() dto: PostDto) {
    return this.g.post(u.firmId, dto);
  }

  @Get('reviews')
  @ApiBearerAuth() @UseGuards(JwtAuthGuard) @Roles(...ADMINS)
  reviews(@CurrentUser() u: JwtPayload) {
    return this.g.reviews(u.firmId);
  }

  @Post('reviews/reply')
  @ApiBearerAuth() @UseGuards(JwtAuthGuard) @Roles(...ADMINS)
  async reply(@CurrentUser() u: JwtPayload, @Body() dto: ReplyDto) {
    await this.g.reply(u.firmId, dto.reviewId, dto.comment);
    return { ok: true };
  }
}

@Module({ controllers: [GoogleProfileController], providers: [GoogleProfileService] })
export class GoogleProfileModule {}
