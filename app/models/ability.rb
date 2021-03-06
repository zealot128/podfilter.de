class Ability
  include CanCan::Ability

  def initialize(user)
    can [:show], OpmlFile
    can [:index, :show], Source

    if user && user.opml_files.count > 0
      can :add, Source
      can :add_source, OpmlFile, owner_id: user.id
      can :remove_source, OpmlFile, owner_id: user.id
    end

    if user && user.admin?
      can :manage, :all
    end

    if user
      can :manage, OpmlFile, owner_id: user.id
      cannot :destroy, OpmlFile, type: 'IgnoreFile'
    end

    if user && user.primary_identity.present?

    end
  end
end
