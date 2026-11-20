module Portal
  class RateCardsController < BaseController
    def show
      @draft = @operator
      load_preview
    end

    def update
      @draft = @operator
      @draft.assign_attributes(rate_card_params)
      if params[:suggest]
        @draft.apply_suggested_rates!
        @status = [ "", helpers.a("suggestedApplied") ]
        load_preview
        render :show, status: :unprocessable_entity # no-JS fallback; Turbo needs a non-2xx to render in place
      elsif @draft.save
        redirect_to portal_rate_card_path, notice: helpers.a("saved")
      else
        @status = [ "bad", @draft.below_floor? ? helpers.a("belowMin") : helpers.a("invalidFleet") ]
        load_preview
        render :show, status: :unprocessable_entity
      end
    end

    # Live preview of an unsaved draft
    def preview
      @draft = @operator.dup.tap { |d| d.id = @operator.id; d.assign_attributes(rate_card_params) }
      d = @draft
      d.send(:normalise_fleet)
      load_preview
      streams = [ turbo_stream.update("rc-preview", partial: "portal/rate_cards/preview") ]
      streams << turbo_stream.update("fleet-body", partial: "portal/rate_cards/fleet_rows", locals: { draft: d }) if params[:depot_changed]
      render turbo_stream: streams
    end

    private

    def rate_card_params
      p = params.require(:operator).permit(:depot, :radius, :pos_factor, :ev, :sur_weekend, :sur_peak, :sur_night,
                                           blocked_dates: [], fleet: Pricing::CLASS_IDS.index_with { %i[count hr km minH] })
      p[:blocked_dates] ||= []
      if p[:fleet]
        submitted = p[:fleet].to_h.transform_values { |v| v.to_h.transform_values(&:to_i) }
        p[:fleet] = @operator.fleet.to_h { |id, card| [ id, card.merge(submitted.fetch(id, {})) ] }.merge(submitted.except(*@operator.fleet.keys))
      end
      p[:pos_factor] = p[:pos_factor].to_f if p[:pos_factor]
      p
    end

    def load_preview
      q = session[:last_query]
      @query = q && Pricing::Query.from_params(q)
      return unless @query&.valid?

      engine = Pricing::Engine.new(@query)
      @mine = engine.price(@draft)
      return unless @mine.ok?

      others = ::Operator.where.not(id: @operator.id).map { |o| engine.price(o) }.select(&:ok?).map(&:total)
      all = (others + [ @mine.total ]).sort
      @rank = [ all.index(@mine.total) + 1, all.size ]
    end
  end
end
