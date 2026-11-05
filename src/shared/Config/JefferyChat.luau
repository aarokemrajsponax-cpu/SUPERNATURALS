-- Ask Jeffery: settings for the chat (JefferyChatService on the server, the Ask Jeffery panel on the
-- client). Everything the owner may want to change is here.
--
-- The offline knowledge base (Config/JefferyKnowledge) always answers. The optional AI provider is
-- OFF by default. To turn it on (owner steps):
--   1. Game Settings > Security > Allow HTTP Requests.
--   2. Creator Hub > Open Cloud > Secrets: add a secret named like Provider.SecretName
--      (ANTHROPIC_API_KEY) holding your key, allowed for the domain api.anthropic.com.
--   3. Set Enabled = true below and publish.
-- The key never appears in code, in a remote or on a client. If the secret is missing the AI
-- stays off and the knowledge base keeps answering.
--
-- Cost (Anthropic list prices, checked 4 Nov 2026; your Anthropic bill, not Roblox's):
--   claude-opus-5-5 (default, the most capable): $4 per million input tokens, $20 per million output.
--   Jeffery's rules and notes (about 3,500 tokens) are sent with a prompt-cache marker, so repeat
--   questions read them at $0.20 per million. One answer costs roughly 0.5 to 1 cent, so the
--   per-server cap below (400 an hour) is at most about $4 per busy server per hour.
--   claude-haiku-5-5: $0.10 / $0.50 per million, about 1/40 of that, with simpler answers. To use
--   it set Model = "claude-haiku-5-5", Fallbacks = nil and Beta = nil (Haiku has no server-side
--   fallback). Which model to pay for is the owner's decision.

local JefferyChat = {}

JefferyChat.Enabled = false

JefferyChat.Provider = {
	Url = "https://api.anthropic.com/v1/messages",
	Model = "claude-opus-5-5",
	MaxTokens = 1024,
	Version = "2026-10-21",
	Beta = "server-side-fallback-2026-07-01",
	Fallbacks = "default",
	Effort = "low",
	SecretName = "ANTHROPIC_API_KEY",
	-- Seconds to wait for the provider before answering from the knowledge base
	TimeoutSeconds = 12,
}

JefferyChat.Limits = {
	-- Characters a player may type
	MaxInput = 200,
	-- Seconds between two questions from one player (every question, AI or not)
	CooldownSeconds = 6,
	-- Questions per player per UTC day that may go to the AI (the knowledge base is not counted)
	PerPlayerPerDay = 30,
	-- Questions per server per hour that may go to the AI (protects the owner's spending)
	PerServerPerHour = 400,
	-- Earlier messages of this player's chat sent along (user and assistant messages together)
	HistoryMessages = 6,
	-- Longest answer shown (characters); longer AI text is cut at a sentence end
	MaxAnswer = 420,
}

JefferyChat.Text = {
	Empty = "Type a question and I will do my best.",
	TooLong = "That is a bit long for me. Please keep it under 200 characters.",
	Wait = "One moment, I am still thinking about your last question. Try again in %d seconds.",
	Busy = "I am still working on your last question.",
	Unknown = "I am not sure about that one. How to Play has the basics, or try asking about controls, fighters, phases, places, the shop or gifts.",
	Refused = "I can only help with friendly questions about SUPERNATURALS.",
	FilterDown = "My word checker is resting, so I will answer from my notes.",
}

return JefferyChat
