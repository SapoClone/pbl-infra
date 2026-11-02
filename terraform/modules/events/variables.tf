variable "topology" {
  description = "Parsed events-topology.json (generated from libs/contracts/src/topology.ts by pbl-api's scripts/export-topology.ts): topics = producing services, queues = consuming service => producer => event types."
  type = object({
    topics = list(string)
    queues = map(map(list(string)))
  })
}

variable "alert_email" {
  description = "Email subscribed to the dead-letter alarms (empty: alarms exist but notify nobody)."
  type        = string
  default     = ""
}

variable "visibility_timeout_seconds" {
  description = "Must match the consumers' EVENTS_VISIBILITY_TIMEOUT (default 30)."
  type        = number
  default     = 30
}

variable "max_receive_count" {
  description = "Receives before a message goes to the DLQ; must match EVENTS_MAX_RECEIVE_COUNT (default 3)."
  type        = number
  default     = 3
}
