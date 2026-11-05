# Roblox regional pricing: verified facts (read 3 November 2026)

Sources (both loaded): create.roblox.com/docs/production/monetization/regional-pricing and the
MarketplaceService reference for GetUsersPriceLevelsAsync.

- `MarketplaceService:GetUsersPriceLevelsAsync(userIds: {number}): {PriceLevelInfo}` yields and
  returns an array of `{ UserId: number, PriceLevel: number }`. PriceLevel is 1 to 1000; 1000 is
  the full global price, lower means a lower managed price (500 = 50%). No per-call id limit is
  documented; the realm (server or client) is not stated. Guidance: "always make calls to
  GetUsersPriceLevelsAsync at player join"; do not keep results beyond the session.
- Transfers: Roblox's examples allow a gift when sender level >= recipient level, and a trade
  only when the two levels are equal.
- Displayed prices: `MarketplaceService:GetProductInfoAsync(id, Enum.InfoType.Product)` for
  developer products and `Enum.InfoType.GamePass` for passes, reading `PriceInRobux`.
  "Dynamically-scripted prices" are ones "called from a client script", so the shop must fetch
  prices on the client for the local player, never hard-code them. `GetProductInfo` (no Async)
  is deprecated. `MarketplaceService:GetDeveloperProductsAsync()` returns pages
  (`:GetCurrentPage()`) to list all developer products with their prices.
- Managed Pricing: on by default for all game passes (can be turned off); NOT on by default for
  developer products. Prerequisites before enabling it on a developer product: prices scripted
  dynamically, and GetUsersPriceLevelsAsync implemented. Then Creator Hub, Monetization,
  Developer Products, select the product, Enable Managed Pricing. Regional prices are never more
  than 70% below the default and never above it.
- Dynamic Price Check: Creator Hub, Monetization, Passes or Developer Products, "..." menu,
  Dynamic Price Check. Up to five Roblox users. "Price pinned" sets a fake Robux amount for all
  dynamically scripted prices; "Location pinned" sets region-specific prices for a fake
  economic location. Enable, wait a few minutes, join the game; disable it afterwards.
