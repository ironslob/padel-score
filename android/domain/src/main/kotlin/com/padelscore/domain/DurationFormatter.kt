package com.padelscore.domain

object DurationFormatter {
    fun countdown(interval: Double): String {
        val total = maxOf(0, interval.toInt())
        val minutes = total / 60
        val seconds = total % 60
        return "%d:%02d".format(minutes, seconds)
    }

    fun elapsed(interval: Double): String {
        val total = maxOf(0, interval.toInt())
        val hours = total / 3600
        val minutes = (total % 3600) / 60
        val seconds = total % 60
        if (hours > 0) {
            return "%d:%02d:%02d".format(hours, minutes, seconds)
        }
        val shownMinutes = maxOf(1, minutes + if (seconds > 0 && minutes == 0) 1 else 0)
        return "$shownMinutes min"
    }

    fun detailed(interval: Double): String {
        val total = maxOf(0, interval.toInt())
        val hours = total / 3600
        val minutes = (total % 3600) / 60
        val seconds = total % 60
        return when {
            hours > 0 -> "${hours}h ${minutes}m"
            minutes > 0 -> "$minutes min"
            else -> "$seconds sec"
        }
    }
}
