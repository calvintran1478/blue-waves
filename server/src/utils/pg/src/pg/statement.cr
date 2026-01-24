class PG::Statement < ::DB::Statement
  def initialize(connection, command : String)
    super(connection, command)
  end

  protected def conn
    connection.as(Connection).connection
  end

  protected def perform_query(args : Enumerable(Bytes)) : ResultSet
    conn = self.conn
    conn.send_parse_message(command)
    conn.send_bind_message(args)
    conn.send_describe_portal_message
    conn.send_execute_message
    conn.send_sync_message
    conn.expect_frame PQ::Frame::ParseComplete
    conn.expect_frame PQ::Frame::BindComplete

    frame = conn.read
    case frame
    when PQ::Frame::RowDescription
      fields = frame.fields
    when PQ::Frame::NoData
      fields = nil
    else
      raise "expected RowDescription or NoData, got #{frame}"
    end
    ResultSet.new(self, fields)
  rescue e : IO::Error
    raise DB::ConnectionLost.new(connection, cause: e)
  end

  protected def perform_query(args : Enumerable) : ResultSet
    puts "Expect DB arguments to be bytes"
    exit 1
  end

  protected def perform_exec(args : Enumerable) : ::DB::ExecResult
    result = perform_query(args)
    result.each { }
    ::DB::ExecResult.new(
      rows_affected: result.rows_affected,
      last_insert_id: 0_i64 # postgres doesn't support this
    )
  rescue e : IO::Error
    raise DB::ConnectionLost.new(connection, cause: e)
  end
end
