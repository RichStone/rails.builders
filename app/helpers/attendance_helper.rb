module AttendanceHelper
  def attendance_streak_emoji(count, limit)
    return "😊" if count.zero?
    return "☠️" if count >= limit
    return "🫠" if count == limit - 1

    "😮"
  end
end
