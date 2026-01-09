# Remove this monkeypatch when we want to drop support for Crystal < 1.0
# Crystal versions above 1.0 should have this already, added in this pr:
# https://github.com/crystal-lang/crystal/pull/10520
{% unless IO::Sized.has_method?(:read_remaining=) %}
  class IO::Sized
    setter read_remaining
  end
{% end %}

class PG::ResultSet < ::DB::ResultSet
  getter rows_affected

  def initialize(statement, @fields : Array(PQ::Field)?)
    super(statement)
    @column_index = -1 # The current column
    @end = false       # Did we read all the rows?
    @rows_affected = 0_i64
    @sized_io = Buffer.new(conn.soc, 1, statement.connection.as(PG::Connection))
  end

  protected def conn
    statement.as(Statement).conn
  end

  def move_next : Bool
    return false if @end

    fields = @fields

    # `move_next` might be called before consuming all rows,
    # in that case we need to skip columns
    if fields && @column_index > -1 && @column_index < fields.size
      while @column_index < fields.size
        skip
      end
    end

    unless fields
      @end = true
      frame = conn.expect_frame PQ::Frame::CommandComplete | PQ::Frame::EmptyQueryResponse
      if frame.is_a?(PQ::Frame::CommandComplete)
        @rows_affected = frame.rows_affected
      end

      conn.expect_frame PQ::Frame::ReadyForQuery
      return false
    end

    if conn.read_next_row_start
      # We ignore these (redundant information)
      conn.read_i32 # size
      conn.read_i16 # ncols
      @column_index = 0
      true
    else
      conn.expect_frame PQ::Frame::ReadyForQuery
      @end = true
      false
    end
  rescue e : IO::Error
    raise DB::ConnectionLost.new(statement.connection, cause: e)
  rescue ex
    @end = true
    raise ex
  end

  def column_count : Int32
    @fields.try(&.size) || 0
  end

  def column_name(index : Int32) : String
    field(index).name
  end

  def column_type(index : Int32)
    decoder(index).type
  end

  def next_column_index : Int32
    @column_index
  end

  def read : Nil
  rescue e : IO::Error
    raise DB::ConnectionLost.new(statement.connection, cause: e)
  end

  def read(&)
    col_bytesize = conn.read_i32
    @sized_io.read_remaining = col_bytesize.to_u64

    value = yield @sized_io, col_bytesize

    conn.soc.skip(@sized_io.read_remaining) if @sized_io.read_remaining > 0
    @column_index += 1

    value
  rescue e : IO::Error
    raise DB::ConnectionLost.new(statement.connection, cause: e)
  end

  private def skip
    col_size = conn.read_i32
    conn.skip_bytes(col_size) if col_size != -1
    @column_index += 1
  rescue e : IO::Error
    raise DB::ConnectionLost.new(statement.connection, cause: e)
  end

  protected def do_close
    super

    # Nothing to do if all the rows were consumed
    return if @end

    # Check if we didn't advance to the first row
    if @column_index == -1
      return unless move_next
    end

    fields = @fields

    loop do
      # Skip remaining columns
      while fields && @column_index < fields.size
        skip
      end

      break unless move_next
    end
  rescue DB::ConnectionLost
    # if the connection is lost there is nothing to be
    # done since the result set is no longer needed
  end

  private class Buffer < IO::Sized
    getter connection : PG::Connection

    def initialize(io, read_size, @connection)
      super io, read_size
    end
  end
end
