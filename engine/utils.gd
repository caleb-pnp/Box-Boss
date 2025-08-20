# If it's a utility script, make it a class_name for easy access:
class_name Utils

static func format_ordinal(number: int) -> String:
	if number <= 0:
		return str(number) # Or "N/A" or handle as error

	# Special cases: 11th, 12th, 13th
	var last_two_digits = number % 100
	if last_two_digits >= 11 and last_two_digits <= 13:
		return str(number) + "th"

	# General cases based on the last digit
	var last_digit = number % 10
	match last_digit:
		1:
			return str(number) + "st"
		2:
			return str(number) + "nd"
		3:
			return str(number) + "rd"
		_: # All other digits (0, 4-9)
			return str(number) + "th"

# This function takes a float (total seconds) and returns a formatted string.
static func format_time(total_seconds: float, show_milliseconds: bool = false) -> String:
	# Calculate total whole minutes
	var minutes = int(total_seconds / 60)

	# Calculate the remaining whole seconds
	var seconds = int(total_seconds) % 60

	# Check the flag to decide which format to use
	if show_milliseconds:
		# Calculate milliseconds from the fractional part of the seconds
		var milliseconds = int(fmod(total_seconds, 1) * 1000)
		# Format with milliseconds, padded to 3 digits (e.g., .045)
		return "in %d min: %02d.%03d sec" % [minutes, seconds, milliseconds]
	else:
		# The original format
		return "in %d min: %02d sec" % [minutes, seconds]


# This function formats time into a "Mario Kart" style: MM' SS'' CS
static func format_time_lap(total_seconds: float) -> String:
	# Handle negative time if it occurs
	if total_seconds < 0:
		total_seconds = 0

	# Calculate minutes and whole seconds
	var minutes = int(total_seconds / 60)
	var seconds = int(total_seconds) % 60

	# Calculate centiseconds (the two-digit millisecond value)
	var centiseconds = int(fmod(total_seconds, 1) * 100)

	# Format the string to match "00' 07'' 55"
	# The %02d specifier pads numbers with a leading zero to 2 digits.
	return "%02d' %02d'' %02d" % [minutes, seconds, centiseconds]
