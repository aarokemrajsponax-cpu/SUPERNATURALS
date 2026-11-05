# Roblox growth APIs: verified facts (read 3 November 2026)

Sources: create.roblox.com docs for Player, SocialService, invite-prompts, referral-system and
AnalyticsService (read through a fetch agent; quotes are the docs' words).

- Referrals: "The ReferredByPlayerId property of GetJoinData() automatically populates for all
  types of invitations and gives you access to the user ID of the referring player." Read it
  from `player:GetJoinData().ReferredByPlayerId` in server `Players.PlayerAdded`; 0 or nil means
  no referrer. Roblox advises one-time rewards per invitee, a cooldown per inviter and monitoring.
  Creator setup: Creator Hub, Creations, the game, Engagement, Referral Rewards, Add Reward
  Details (icon, name, dates, optional limit per inviter), Save, Publish. The game must have
  been live for at least one day. Only one reward banner shows at a time.
- Invites: `SocialService:CanSendGameInviteAsync(player)` (yields, wrap in pcall) and
  `SocialService:PromptGameInvite(player, ExperienceInviteOptions?)` from a LocalScript.
  ExperienceInviteOptions: PromptMessage (string, hidden if too long), InviteUser (UserId),
  InviteMessageId (a Notification string asset the creator makes under Engagement,
  Notifications; must contain {experienceName}), LaunchData (string, max 200 characters; read
  back through GetJoinData().LaunchData, can take a few seconds, retry). Event:
  `SocialService.GameInvitePromptClosed(player, recipientIds)`.
- Analytics: `AnalyticsService:LogOnboardingFunnelStepEvent(player, step, stepName, customFields?)`,
  `LogFunnelStepEvent(player, funnelName, funnelSessionId, step, stepName, customFields?)`,
  `LogProgressionEvent(player, pathName, Enum.AnalyticsProgressionType, level, levelName, customFields?)`,
  `LogEconomyEvent(player, Enum.AnalyticsEconomyFlowType, currencyType, amount, endingBalance, transactionType, itemSku, customFields?)`,
  `LogCustomEvent(player, eventName, value?, customFields?)`. No limits are stated; call through pcall.
- Groups: `player:IsInGroup(groupId)` (yields; pcall). The group id comes from the owner.
- Not available in-game: verifying likes, favourites or ratings; rewarding Discord membership
  (off-platform). Social links (Discord and others) go on the experience page in Creator Hub.
