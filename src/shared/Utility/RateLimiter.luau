-- Token-bucket rate limiting: each key may act `rate` times per second on
-- average, with short bursts up to `burst`. Used to reject remote spam.

local RateLimiter = {}

export type Limiter = {
	rate: number,
	burst: number,
	buckets: { [any]: { tokens: number, updatedAt: number } },
}

function RateLimiter.new(rate: number, burst: number): Limiter
	return { rate = rate, burst = burst, buckets = {} }
end

function RateLimiter.allow(limiter: Limiter, key: any, now: number, cost: number?): boolean
	local price = cost or 1
	local bucket = limiter.buckets[key]
	if not bucket then
		bucket = { tokens = limiter.burst, updatedAt = now }
		limiter.buckets[key] = bucket
	end
	local elapsed = math.max(0, now - bucket.updatedAt)
	bucket.tokens = math.min(limiter.burst, bucket.tokens + elapsed * limiter.rate)
	bucket.updatedAt = now
	if bucket.tokens < price then
		return false
	end
	bucket.tokens -= price
	return true
end

function RateLimiter.forget(limiter: Limiter, key: any)
	limiter.buckets[key] = nil
end

return RateLimiter
