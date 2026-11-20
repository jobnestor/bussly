# Bussly Bedrift: recurring shuttles and invoiced travel for companies, schools and events
class BusinessController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 10, within: 10.minutes, only: :create, with: -> { head :too_many_requests }

  def new
    @lead = ShuttleRequest.new(segment: "commute")
  end

  def create
    @lead = ShuttleRequest.new(lead_params)
    if @lead.save
      redirect_to business_path, notice: helpers.a("biz.thanks")
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def lead_params
    p = params.require(:shuttle_request).permit(:company, :contact_name, :email, :phone, :segment, :route, :riders, :start_date, :notes, weekdays: [])
    p[:weekdays] = Array(p[:weekdays]).select { |d| ShuttleRequest::WEEKDAYS.include?(d) }.join(",")
    p
  end
end
