module Portal
  class RequestsController < BaseController
    def index
      mine = @operator.bookings.order(:date)
      @new = mine.where(status: "new")
      @open = Booking.open_jobs.order(:date)
      @rows = @new.to_a + @open.to_a + mine.where.not(status: "new").to_a
      @accepted = mine.where(status: %w[ok paid])
      @revenue = @accepted.sum(:subtotal)
    end

    def accept = transition("new", "ok")
    def decline = transition("new", "no")

    # Open guarantee jobs: first operator to claim gets it (atomic update guards the race)
    def claim
      n = Booking.where(ref: params[:ref], status: "src", operator_id: nil).update_all(operator_id: @operator.id, status: "ok", updated_at: Time.current)
      redirect_to portal_root_path, notice: n == 1 ? helpers.a("claimed") : nil, alert: n == 1 ? nil : helpers.a("claimTaken")
    end

    # Assign driver and vehicle; the customer and passengers see them on the trip and tracking pages
    def assign
      booking = @operator.bookings.find_by!(ref: params[:ref])
      booking.assign_attributes(params.require(:booking).permit(:driver_name, :driver_phone, :vehicle_plate))
      if booking.confirmed? && booking.save(context: :assign_driver)
        redirect_to portal_root_path, notice: helpers.a("portal.assigned", ref: booking.ref)
      else
        redirect_to portal_root_path, alert: helpers.a("portal.assignErr")
      end
    end

    def complete
      booking = @operator.bookings.find_by!(ref: params[:ref])
      booking.complete!
      redirect_to portal_root_path, notice: helpers.a("portal.completed", ref: booking.ref)
    end

    private

    def transition(from, to)
      @operator.bookings.where(ref: params[:ref], status: from).update_all(status: to, updated_at: Time.current)
      redirect_to portal_root_path
    end
  end
end
