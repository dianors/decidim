# frozen_string_literal: true

require "spec_helper"

module Decidim
  module Comments
    describe CreateRegistration do
      describe "call" do
        let(:organization) { create(:organization) }

        let(:name) { "Username" }
        let(:nickname) { "nickname" }
        let(:email) { "user@example.org" }
        let(:password) { "Y1fERVzL2F" }
        let(:password_confirmation) { password }
        let(:tos_agreement) { "1" }
        let(:newsletter) { "1" }

        let(:form_params) do
          {
            "user" => {
              "name" => name,
              "nickname" => nickname,
              "email" => email,
              "password" => password,
              "password_confirmation" => password_confirmation,
              "tos_agreement" => tos_agreement,
              "newsletter" => newsletter
            }
          }
        end
        let(:form) do
          RegistrationForm.from_params(
            form_params
          ).with_context(
            current_organization: organization
          )
        end
        let(:command) { described_class.new(form) }

        describe "when the form is not valid" do
          before do
            expect(form).to receive(:invalid?).and_return(true)
          end

          it "broadcasts invalid" do
            expect { command.call }.to broadcast(:invalid)
          end

          it "doesn't create a user" do
            expect do
              command.call
            end.not_to change(User, :count)
          end
        end

        describe "when the form is valid" do
          it "broadcasts ok" do
            expect { command.call }.to broadcast(:ok)
          end

          it "creates a new user" do
            expect(User).to receive(:create!).with(
              name: form.name,
              nickname: form.nickname,
              email: form.email,
              password: form.password,
              password_confirmation: form.password_confirmation,
              tos_agreement: form.tos_agreement,
              newsletter_notifications_at: form.newsletter_at,
              email_on_notification: true,
              organization: organization,
              accepted_tos_version: organization.tos_version
            ).and_call_original

            expect { command.call }.to change(User, :count).by(1)
          end

          describe "when user keep uncheck newsletter" do
            let(:newsletter) { "0" }

            it "creates a user with no newsletter notifications" do
              expect do
                command.call
                expect(User.last.newsletter_notifications_at).to eq(nil)
              end.to change(User, :count).by(1)
            end
          end

          context "when a user was invited but never accepted" do
            let(:name) { "Abril 23" }
            let(:nickname) { "lexercitdelfenix" }
            let!(:pending_user) do
              create(:user, email: email, organization: organization, invitation_token: "foobar", invitation_accepted_at: nil)
            end

            it "deletes the previous user and creates a new one" do
              previous_pwd = pending_user.encrypted_password
              expect do
                command.call
              end.to(change(Decidim::User, :count).by(0) && change(enqueued_jobs, :size).by(+1))

              expect(pending_user.reload.name).to eq(name)
              expect(pending_user.nickname).to eq(nickname)
              expect(pending_user.encrypted_password).not_to eq(previous_pwd)
              expect(pending_user.newsletter_notifications_at).to be_present
              expect(pending_user.email_on_notification).to be true
              expect(pending_user.accepted_tos_version.to_s).to eq(organization.tos_version.to_s)
              expect(enqueued_jobs.first[:args].include?("confirmation_instructions")).to be(true)
            end
          end
        end
      end
    end
  end
end
